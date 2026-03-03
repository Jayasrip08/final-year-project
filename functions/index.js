/**
 * A-DACS - Cloud Functions
 * 
 * This file contains all Cloud Functions for:
 * 1. Automated payment deadline reminders
 * 2. Payment status change notifications
 * 3. Student activity tracking
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");
const { onCall, HttpsError } = require("firebase-functions/v2/https"); // NEW
const emailService = require("./email_service.js");
const smsService = require("./sms_service.js"); // NEW

// Initialize Firebase Admin
admin.initializeApp();

// helper to count unread notifications for a user
async function getUnreadCount(userId) {
  if (!userId) return 0;
  try {
    const snap = await admin.firestore()
      .collection('notifications')
      .where('userId', '==', userId)
      .where('read', '==', false)
      .count()
      .get();
    return snap.count || 0;
  } catch (err) {
    logger.error('Error fetching unread count for', userId, err);
    return 0;
  }
}

// helper to send FCM message and log it to Firestore with badge count
// messagePayload should include notification, data, android, etc. but not
// token.  The function will add the token and badge fields, write the log,
// and return the FCM response string.
async function sendUserNotification(userId, fcmToken, messagePayload) {
  const db = admin.firestore();

  // first create log entry (without fcmMessageId)
  const logDoc = await db.collection('notifications').add({
    userId,
    type: messagePayload.data?.type || '',
    title: messagePayload.notification?.title || '',
    body: messagePayload.notification?.body || '',
    data: messagePayload.data || {},
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
    read: false,
  });

  // recalc unread count now that the new document exists
  const count = await getUnreadCount(userId);

  // attach badge info to payload for both iOS and Android
  messagePayload.android = messagePayload.android || {};
  messagePayload.android.notification = messagePayload.android.notification || {};
  messagePayload.android.notification.number = count;

  messagePayload.apns = messagePayload.apns || {};
  messagePayload.apns.payload = messagePayload.apns.payload || {};
  messagePayload.apns.payload.aps = messagePayload.apns.payload.aps || {};
  messagePayload.apns.payload.aps.badge = count;

  // send the note
  const fullMessage = {token: fcmToken, ...messagePayload};
  const response = await admin.messaging().send(fullMessage);

  // update log with the FCM message id
  await logDoc.update({ fcmMessageId: response });

  return response;
}

// Set global options for all functions
setGlobalOptions({
  maxInstances: 10,
  region: "asia-south1", // Mumbai region for India
});

/**
 * Scheduled function to send payment deadline reminders
 * Runs daily at 10:00 AM IST
 */
exports.sendEmailMethods = emailService.sendEmailReminders;
exports.sendPaymentReminders = onSchedule({
  schedule: "0 10 * * *", // Every day at 10:00 AM
  timeZone: "Asia/Kolkata",
  region: "asia-south1",
  secrets: ["TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_PHONE_NUMBER"],
}, async (event) => {
  logger.info("Starting payment reminder job");

  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  const nowDate = now.toDate();

  try {
    // Get all active semesters
    const semestersSnapshot = await db.collection("semesters")
      .where("isActive", "==", true)
      .get();

    logger.info(`Found ${semestersSnapshot.size} active semesters`);

    for (const semDoc of semestersSnapshot.docs) {
      const semester = semDoc.data();

      // Get fee structures for this semester
      const feeStructuresSnapshot = await db.collection("fee_structures")
        .where("semester", "==", semDoc.id)
        .get();

      logger.info(`Processing ${feeStructuresSnapshot.size} fee structures for ${semDoc.id}`);

      for (const feeDoc of feeStructuresSnapshot.docs) {
        const feeData = feeDoc.data();

        // Check if deadline exists
        if (!feeData.deadline) continue;

        const deadline = feeData.deadline.toDate();
        const daysUntilDeadline = Math.ceil(
          (deadline.getTime() - nowDate.getTime()) / (1000 * 60 * 60 * 24),
        );

        logger.info(`Deadline in ${daysUntilDeadline} days for ${feeDoc.id}`);

        // Send reminder if deadline is in 7, 3, or 1 day(s)
        if ([7, 3, 1].includes(daysUntilDeadline)) {
          await sendRemindersForFeeStructure(
            feeDoc.id,
            feeData,
            daysUntilDeadline,
          );
        }
      }
    }

    logger.info("Payment reminder job completed successfully");
    return null;
  } catch (error) {
    logger.error("Error in payment reminder job:", error);
    throw error;
  }
});

/**
 * Trigger when a fee structure is created or updated
 * Sends SMS to parents about the new/changed fee
 */
exports.onFeeStructureChanged = onDocumentCreated({
  document: "fee_structures/{docId}",
  region: "asia-south1",
  secrets: ["TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_PHONE_NUMBER"],
}, async (event) => {
  const feeData = event.data.data();
  const db = admin.firestore();

  try {
    const academicYear = feeData.academicYear;
    const dept = feeData.dept;
    const quota = feeData.quotaCategory;
    const semester = feeData.semester;
    const totalAmount = feeData.totalAmount;
    const deadlineText = feeData.deadline ? feeData.deadline.toDate().toLocaleDateString() : "N/A";

    logger.info(`New fee structure detected for ${academicYear} ${dept} ${quota}. Notifying students.`);

    // Find all matching students
    let query = db.collection("users")
      .where("role", "==", "student")
      .where("batch", "==", academicYear);

    if (dept !== "All") query = query.where("dept", "==", dept);
    if (quota !== "All") query = query.where("quotaCategory", "==", quota);

    const studentsSnapshot = await query.get();
    const smsPromises = [];

    for (const studentDoc of studentsSnapshot.docs) {
      const studentData = studentDoc.data();
      if (studentData.parentPhoneNumber) {
        smsPromises.push(smsService.sendFeeChangeSMS(
          studentData.parentPhoneNumber,
          semester,
          totalAmount,
          deadlineText,
        ));
      }
    }

    await Promise.all(smsPromises);
    logger.info(`Sent fee change SMS to ${smsPromises.length} parents.`);
  } catch (error) {
    logger.error("Error in onFeeStructureChanged:", error);
  }
});

/**
 * Callable function for admins to manually trigger overdue SMS
 */
exports.triggerManualOverdueSMS = onCall({
  region: "asia-south1",
  secrets: ["TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_PHONE_NUMBER"],
}, async (request) => {
  // 1. Verify Authentication & Admin Role
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "The function must be called while authenticated.");
  }

  const callerUid = request.auth.uid;
  const db = admin.firestore();
  const callerDoc = await db.collection("users").doc(callerUid).get();

  if (!callerDoc.exists || callerDoc.data().role !== "admin") {
    throw new HttpsError("permission-denied", "Only admins can trigger manual SMS.");
  }

  const { studentId, amount, deadline } = request.data;
  if (!studentId || !amount || !deadline) {
    throw new HttpsError("invalid-argument", "Missing required parameters (studentId, amount, deadline).");
  }

  try {
    const studentDoc = await db.collection("users").doc(studentId).get();
    if (!studentDoc.exists) {
      throw new HttpsError("not-found", "Student not found.");
    }

    const studentData = studentDoc.data();
    if (!studentData.parentPhoneNumber) {
      return { success: false, message: "Student has no parent phone number registered." };
    }

    await smsService.sendOverdueSMS(
      studentData.parentPhoneNumber,
      amount,
      deadline,
    );

    return { success: true, message: "SMS sent successfully." };
  } catch (error) {
    logger.error("Error triggering manual SMS:", error);
    throw new HttpsError("internal", error.message);
  }
});

/**
 * Helper function to send reminders for a specific fee structure
 */
async function sendRemindersForFeeStructure(
  feeStructureId,
  feeData,
  daysUntilDeadline,
) {
  const db = admin.firestore();

  try {
    // Find students matching this fee structure who haven't paid
    const usersSnapshot = await db.collection("users")
      .where("role", "==", "student")
      .where("dept", "==", feeData.dept)
      .where("quotaCategory", "==", feeData.quotaCategory)
      .where("status", "==", "Pending") // Only unpaid students
      .get();

    logger.info(`Found ${usersSnapshot.size} students to remind for ${feeStructureId}`);

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const fcmToken = userData.fcmToken;

      if (!fcmToken) {
        logger.warn(`No FCM token for user ${userDoc.id}`);
        continue;
      }

      // Calculate outstanding amount
      const outstandingAmount = feeData.amount - (userData.paidFee || 0);

      if (outstandingAmount <= 0) {
        // Student has already paid
        continue;
      }

      // Prepare notification message
      const title = "⚠️ Fee Payment Reminder";
      const body = `Your fee payment deadline is in ${daysUntilDeadline} day(s). Amount due: ₹${outstandingAmount}`;

      const baseMessage = {
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: "payment_reminder",
          amount: String(outstandingAmount),
          deadline: feeData.deadline.toDate().toISOString(),
          daysRemaining: String(daysUntilDeadline),
        },
        android: {
          priority: "high",
          notification: {
            sound: "default",
            color: "#FF6B35",
          },
        },
      };

      try {
        // write log, calculate badge count and send via helper
        const response = await sendUserNotification(userDoc.id, fcmToken, baseMessage);
        logger.info(`Notification sent to ${userData.email}: ${response}`);

        // Send SMS to parent if phone exists
        if (userData.parentPhoneNumber) {
          const deadlineText = feeData.deadline.toDate().toLocaleDateString();
          await smsService.sendOverdueSMS(
            userData.parentPhoneNumber,
            outstandingAmount,
            deadlineText,
          );
        }
      } catch (error) {
        logger.error(`Failed to send notification to ${userData.email}:`, error);
      }
    }
  } catch (error) {
    logger.error(`Error sending reminders for ${feeStructureId}:`, error);
  }
}

/**
 * Trigger when payment status changes
 * Sends notification to student when admin verifies or rejects payment
 */
exports.onPaymentStatusChangeV2 = onDocumentUpdated({
  document: "payments/{paymentId}",
  region: "asia-south1",
  secrets: ["TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_PHONE_NUMBER"],
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  // Check if status changed
  if (before.status === after.status) {
    return null;
  }

  logger.info(`Payment status changed from ${before.status} to ${after.status} for payment ${event.params.paymentId}`);

  const db = admin.firestore();

  try {
    // Get student data
    const studentDoc = await db.collection("users").doc(after.studentId).get();

    if (!studentDoc.exists) {
      logger.error(`Student not found: ${after.studentId}`);
      return null;
    }

    const studentData = studentDoc.data();
    const fcmToken = studentData.fcmToken;

    if (!fcmToken) {
      logger.warn(`No FCM token for student ${after.studentId}`);
      return null;
    }

    let title = "";
    let body = "";
    let notificationType = "";

    // Prepare notification based on new status
    if (after.status === "verified") {
      title = "✅ Payment Verified";
      body = `Your payment of ₹${after.amount} has been verified successfully!`;
      notificationType = "payment_verified";
    } else if (after.status === "rejected") {
      title = "❌ Payment Rejected";
      body = `Your payment was rejected. ${after.rejectionReason ? "Reason: " + after.rejectionReason : "Please contact admin."}`;
      notificationType = "payment_rejected";
    } else if (after.status === "under_review") {
      title = "🔍 Payment Under Review";
      body = `Your payment of ₹${after.amount} is being reviewed by the admin.`;
      notificationType = "payment_under_review";
    } else {
      // Unknown status, don't send notification
      return null;
    }

    const baseMessage = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: notificationType,
        status: after.status,
        paymentId: event.params.paymentId,
        amount: String(after.amount),
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
          color: after.status === "verified" ? "#4CAF50" : "#F44336",
        },
      },
    };

    const response = await sendUserNotification(after.studentId, fcmToken, baseMessage);
    logger.info(`Status change notification sent to ${studentData.email}: ${response}`);

    // Send Email notification
    await emailService.sendPaymentStatusEmail(after, studentData.email, studentData.name);

    // Send SMS to parent if payment is verified
    if (after.status === "verified" && studentData.parentPhoneNumber) {
      await smsService.sendPaymentConfirmedSMS(
        studentData.parentPhoneNumber,
        after.amount,
        after.feeType,
      );
    }

    return null;
  } catch (error) {
    logger.error("Error sending payment status notification:", error);
    throw error;
  }
});

/**
 * Helper function to calculate peak activity time for a user
 * Analyzes user's activity patterns to send notifications at optimal times
 */
async function calculatePeakActivityTime(userId) {
  const db = admin.firestore();

  try {
    const userDoc = await db.collection("users").doc(userId).get();

    if (!userDoc.exists) {
      return 10; // Default to 10 AM
    }

    const lastActiveAt = userDoc.data().lastActiveAt;

    if (lastActiveAt) {
      const hour = lastActiveAt.toDate().getHours();
      return hour;
    }

    return 10; // Default to 10 AM
  } catch (error) {
    logger.error(`Error calculating peak time for ${userId}:`, error);
    return 10;
  }
}

/**
 * Trigger when a new user is created
 * Sends welcome notification
 */
exports.onUserCreated = onDocumentUpdated({
  document: "users/{userId}",
  region: "asia-south1",
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  // Check if fcmToken was just added (user logged in for first time)
  if (!before.fcmToken && after.fcmToken && after.role === "student") {
    const db = admin.firestore();

    const baseMessage = {
      notification: {
        title: "Welcome to A-DACS",
        body: `Hello ${after.name}! You can now manage your fee payments digitally.`,
      },
      data: {
        type: "welcome",
      },
    };

    try {
      const response = await sendUserNotification(event.params.userId, after.fcmToken, baseMessage);
      logger.info(`Welcome notification sent to ${after.email}`);
    } catch (error) {
      logger.error(`Failed to send welcome notification:`, error);
    }
  }

  return null;
});

/**
 * Trigger when a student uploads a new payment receipt
 * Notifies Staff members in that department
 */
exports.onPaymentCreated = onDocumentCreated({
  document: "payments/{paymentId}",
  region: "asia-south1",
}, async (event) => {
  const paymentData = event.data.data();
  const db = admin.firestore();

  try {
    // 1. Find Staff in the same department
    const staffSnapshot = await db.collection("users")
      .where("role", "==", "staff")
      .where("dept", "==", paymentData.dept)
      .get();

    const title = "📄 New Payment Receipt";
    const body = `${paymentData.studentName} uploaded a receipt for ${paymentData.feeType}.`;

    const notifications = [];
    for (const staffDoc of staffSnapshot.docs) {
      const staffData = staffDoc.data();
      if (staffData.fcmToken) {
        const baseMessage = {
          notification: { title, body },
          data: {
            type: "new_payment",
            paymentId: event.params.paymentId,
            studentId: paymentData.studentId,
          },
        };
        // sendUserNotification handles log + badge count
        notifications.push(sendUserNotification(staffDoc.id, staffData.fcmToken, baseMessage));
      }
    }
    await Promise.all(notifications);
    logger.info(`Notified ${staffSnapshot.size} staff members of new payment`);
  } catch (error) {
    logger.error("Error in onPaymentCreated:", error);
  }
});

/**
 * Trigger when a new user registers
 * Notifies Admins
 */
exports.onNewRegistration = onDocumentCreated({
  document: "users/{userId}",
  region: "asia-south1",
  secrets: ["TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_PHONE_NUMBER"],
}, async (event) => {
  const userData = event.data.data();
  const db = admin.firestore();

  try {
    // Only notify if it's a student registration
    if (userData.role !== "student") return;

    // 1. Send Welcome SMS to Parent with Fee Details
    if (userData.parentPhoneNumber) {
      try {
        // Find matching active fee structure
        const feeSnapshot = await db.collection("fee_structures")
          .where("isActive", "==", true)
          .where("dept", "in", [userData.dept, "All"])
          .where("quotaCategory", "in", [userData.quotaCategory, "All"])
          .get();

        let totalAmount = "Pending";
        if (!feeSnapshot.empty) {
          // Filter by batch client-side or use the first matching one
          const matchingFee = feeSnapshot.docs.find((doc) => {
            const data = doc.data();
            return !data.batch || data.batch === userData.batch;
          });
          if (matchingFee) {
            totalAmount = matchingFee.data().totalAmount;
          }
        }

        await smsService.sendWelcomeFeeSMS(
          userData.parentPhoneNumber,
          userData.name,
          userData.dept,
          totalAmount,
          "Adhiparasakthi Engineering College",
        );
      } catch (smsErr) {
        logger.error("Error sending welcome SMS:", smsErr);
      }
    }

    // 2. Notify Admins (Existing Logic)
    const adminSnapshot = await db.collection("users")
      .where("role", "==", "admin")
      .get();

    const title = "👤 New Student Registration";
    const body = `New student registered: ${userData.name} (${userData.regNo}).`;

    const notifications = [];
    for (const adminDoc of adminSnapshot.docs) {
      const adminData = adminDoc.data();
      if (adminData.fcmToken) {
        const baseMessage = {
          notification: { title, body },
          data: {
            type: "new_registration",
            userId: event.params.userId,
          },
        };
        notifications.push(sendUserNotification(adminDoc.id, adminData.fcmToken, baseMessage));
      }
    }
    await Promise.all(notifications);
    logger.info(`Notified ${adminSnapshot.size} admins of new registration`);
  } catch (error) {
    logger.error("Error in onNewRegistration:", error);
  }
});

/**
 * Trigger when No-Due certificate status changes
 * Notifies student when admin approves/rejects reissue request
 */
exports.onNoDueStatusChange = onDocumentUpdated({
  document: "no_due_certificates/{certDocId}",
  region: "asia-south1",
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  // Check if status changed
  if (before.status === after.status) {
    return null;
  }

  logger.info(`No-Due status changed for ${event.params.certDocId}: ${before.status} -> ${after.status}`);

  const db = admin.firestore();

  try {
    // get uid from docId (uid_semester format)
    const userId = event.params.certDocId.split('_')[0];
    const userDoc = await db.collection("users").doc(userId).get();

    if (!userDoc.exists || !userDoc.data().fcmToken) return null;

    const userData = userDoc.data();
    let title = "";
    let body = "";
    let type = "";

    if (after.status === "reissue_approved") {
      title = "🔓 No-Due Reissue Approved";
      body = `Your request to re-download the No-Due certificate for ${after.semester} semester has been approved.`;
      type = "no_due_approved";
    } else if (after.status === "issued" && before.status === "reissue_requested") {
      title = "❌ Reissue Request Rejected";
      body = `Your request for a No-Due certificate reissue for ${after.semester} semester was rejected by admin.`;
      type = "no_due_rejected";
    } else {
      return null;
    }

    const baseMessage = {
      notification: { title, body },
      data: {
        type: type,
        semester: after.semester,
      },
    };

    await sendUserNotification(userId, userData.fcmToken, baseMessage);

  } catch (error) {
    logger.error("Error in onNoDueStatusChange:", error);
  }
  return null;
});
