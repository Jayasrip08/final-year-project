importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-app.js");
importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-messaging.js");

firebase.initializeApp({
    apiKey: "AIzaSyBBHlVtdqEHy7LyGsBPPNnylRxbV8nBjB0",
    authDomain: "apec-no-dues.firebaseapp.com",
    projectId: "apec-no-dues",
    storageBucket: "apec-no-dues.firebasestorage.app",
    messagingSenderId: "481537812306",
    appId: "1:481537812306:web:029f26ada45b2d238b3c8b",
    measurementId: "G-ZPVRNXPE82"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
    console.log('[firebase-messaging-sw.js] Received background message ', payload);
    // Customize notification here
    const notificationTitle = payload.notification.title;
    const notificationOptions = {
        body: payload.notification.body,
        icon: '/icons/Icon-192.png'
    };

    self.registration.showNotification(notificationTitle, notificationOptions);
});
