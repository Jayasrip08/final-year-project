const twilio = require("twilio");
const logger = require("firebase-functions/logger");

let client;

/**
 * Lazy-initializes the Twilio client using environment variables.
 * @returns {Twilio}
 */
function getTwilioClient() {
  if (client) return client;

  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;

  if (!accountSid || !authToken) {
    logger.error("SMS Error: TWILIO_ACCOUNT_SID or TWILIO_AUTH_TOKEN is not set in secrets.");
    return null;
  }

  try {
    client = twilio(accountSid, authToken);
    return client;
  } catch (err) {
    logger.error("SMS Error: Failed to initialize Twilio client:", err);
    return null;
  }
}

/**
 * Sends a bilingual SMS message (English and Tamil)
 * @param {string} to Phone number with country code (e.g., +919876543210)
 * @param {string} englishBody English text
 * @param {string} tamilBody Tamil text
 */
async function sendBilingualSMS(to, englishBody, tamilBody) {
  if (!to) {
    logger.warn("SMS: No phone number provided");
    return;
  }

  const twilioClient = getTwilioClient();
  const twilioNumber = process.env.TWILIO_PHONE_NUMBER;

  if (!twilioClient) {
    logger.error("SMS: Twilio client not initialized. Check secrets.");
    return;
  }

  if (!twilioNumber) {
    logger.error("SMS: TWILIO_PHONE_NUMBER is not set in secrets.");
    return;
  }

  // Ensure number has country code for India if not present
  let formattedTo = to;
  if (!to.startsWith("+")) {
    formattedTo = "+91" + to;
  }

  const combinedBody = process.env.SMS_TRIAL_MODE === "true"
    ? englishBody
    : `${englishBody}\n\n${tamilBody}`;

  try {
    const message = await twilioClient.messages.create({
      body: combinedBody,
      from: twilioNumber,
      to: formattedTo,
    });
    logger.info(`SMS sent successfully to ${formattedTo}. SID: ${message.sid}`);
  } catch (error) {
    logger.error(`SMS: Twilio rejected message to ${formattedTo}:`, error.message);
  }
}

/**
 * Template for Fee Structure/Change Notification
 */
async function sendFeeChangeSMS(to, semester, amount, deadline) {
  // Temporarily disabled
  // await sendBilingualSMS(to, english, tamil);
}

/**
 * Template for Overdue Reminder
 */
async function sendOverdueSMS(to, amount, deadline) {
  const english = `URGENT: Fee ₹${amount} is OVERDUE. Pay by ${deadline} at APEC portal.`;
  const tamil = `அவசரம்: கட்டணம் ₹${amount} நிலுவையில் உள்ளது. ${deadline}-க்குள் செலுத்தவும்.`;

  await sendBilingualSMS(to, english, tamil);
}

/**
 * Template for Payment Confirmation
 */
async function sendPaymentConfirmedSMS(to, amount, feeType) {
  // Temporarily disabled
  // await sendBilingualSMS(to, english, tamil);
}

/**
 * Template for Registration Welcome with Fee Details
 */
async function sendWelcomeFeeSMS(to, studentName, dept, totalAmount, collegeName) {
  // Temporarily disabled
  // await sendBilingualSMS(to, english, tamil);
}

module.exports = {
  sendFeeChangeSMS,
  sendOverdueSMS,
  sendPaymentConfirmedSMS,
  sendWelcomeFeeSMS,
};
