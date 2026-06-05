/**
 * Cloud Functions — Intelligent Glove for Arabic Sign Language
 * ───────────────────────────────────────────────────────────────────────────
 * These functions are an OPTIONAL server-side layer. The Flutter `GloveBackend`
 * already performs alert generation, logging and counter updates on the client
 * (so the app works on the free Spark plan). Cloud Functions require the Blaze
 * plan and add capabilities the client cannot do itself.
 *
 * ALWAYS-ON (additive, safe to deploy):
 *   • sendAlertPush     — push an FCM notification whenever an alert is created
 *   • reserveUsername   — secure, server-validated username claim (callable)
 *
 * GATED (set ENABLE_SERVER_SIDE_ALERTS=true to turn on; then REMOVE the
 * matching client-side logic in GloveBackend to avoid double writes):
 *   • onDeviceStatusChanged    — create connectionLogs + alerts on the server
 *   • aggregateSessionOnEnd    — recompute session totals from gestureReadings
 * ───────────────────────────────────────────────────────────────────────────
 */

const {onDocumentCreated, onDocumentWritten, onDocumentUpdated} =
  require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const logger = require("firebase-functions/logger");

initializeApp();
const db = getFirestore();

const SERVER_SIDE_ALERTS = process.env.ENABLE_SERVER_SIDE_ALERTS === "true";

// ════════════════════════════════════════════════════════════════════════════
//  sendAlertPush — fan an alert out to the user's devices via FCM
// ════════════════════════════════════════════════════════════════════════════
exports.sendAlertPush = onDocumentCreated("alerts/{alertId}", async (event) => {
  const alert = event.data?.data();
  if (!alert) return;

  const tokensSnap = await db
      .collection("users").doc(alert.userId)
      .collection("fcmTokens").get();

  const tokens = tokensSnap.docs.map((d) => d.id);
  if (tokens.length === 0) {
    logger.info(`No FCM tokens for user ${alert.userId}; skipping push.`);
    return;
  }

  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: {title: alert.title, body: alert.message},
    data: {
      alertId: event.params.alertId,
      alertType: String(alert.alertType || ""),
      deviceId: String(alert.deviceId || ""),
      severity: String(alert.severity || "low"),
    },
    android: {priority: "high"},
    apns: {payload: {aps: {sound: "default"}}},
  });

  // Prune tokens FCM reports as no longer valid.
  const stale = [];
  response.responses.forEach((r, i) => {
    const code = r.error?.code;
    if (code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token") {
      stale.push(tokensSnap.docs[i].ref.delete());
    }
  });
  await Promise.all(stale);

  logger.info(`Alert ${event.params.alertId}: ${response.successCount} sent, ` +
    `${response.failureCount} failed, ${stale.length} stale tokens removed.`);
});

// ════════════════════════════════════════════════════════════════════════════
//  reserveUsername — secure username claim (callable from the app)
//  Use this instead of the client transaction if you want all validation
//  enforced on the server. Returns { ok: true } or throws.
// ════════════════════════════════════════════════════════════════════════════
exports.reserveUsername = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }
  const uid = request.auth.uid;
  const username = String(request.data?.username || "").trim().toLowerCase();

  if (!/^[a-z0-9_]{3,20}$/.test(username)) {
    throw new HttpsError("invalid-argument",
        "Username must be 3–20 chars: a–z, 0–9, underscore.");
  }

  const ref = db.collection("usernames").doc(username);
  try {
    await db.runTransaction(async (txn) => {
      const snap = await txn.get(ref);
      if (snap.exists) {
        throw new HttpsError("already-exists", "Username is already taken.");
      }
      txn.set(ref, {uid, createdAt: FieldValue.serverTimestamp()});
    });
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("internal", "Could not reserve username.");
  }
  return {ok: true, username};
});

// ════════════════════════════════════════════════════════════════════════════
//  onDeviceStatusChanged  (GATED — server-side connection logs + alerts)
// ════════════════════════════════════════════════════════════════════════════
exports.onDeviceStatusChanged =
  onDocumentWritten("devices/{deviceId}", async (event) => {
    if (!SERVER_SIDE_ALERTS) return; // disabled by default

    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after || !before) return; // ignore create/delete here

    const deviceId = event.params.deviceId;
    const uid = after.ownerId;
    const name = after.deviceName || "Smart Glove";
    const writes = [];

    // ── connection transition ──
    if (before.connectionStatus !== after.connectionStatus) {
      const map = {
        connected: before.connectionStatus === "lost" ?
          ["connection_restored", "Connection restored", `${name} is back online.`, "low"] :
          ["connected", "Device connected", `${name} is now connected.`, "low"],
        disconnected:
          ["disconnected", "Device disconnected", `${name} has been disconnected.`, "medium"],
        lost:
          ["connection_lost", "Connection lost", `Lost connection to ${name}.`, "high"],
      };
      const [eventType, title, message, severity] = map[after.connectionStatus] || [];
      if (eventType) {
        writes.push(createLog(uid, deviceId, name, eventType, after.batteryLevel || 0));
        writes.push(createAlert(uid, deviceId, eventType, title, message, severity));
      }
    }

    // ── battery transition ──
    if (before.batteryStatus !== after.batteryStatus) {
      const pct = after.batteryLevel || 0;
      if (after.batteryStatus === "critical") {
        writes.push(createAlert(uid, deviceId, "battery_critical", "Battery critical",
            `${name} battery is at ${pct}%. Charge now.`, "critical"));
      } else if (after.batteryStatus === "low") {
        writes.push(createAlert(uid, deviceId, "battery_low", "Battery low",
            `${name} battery is at ${pct}%.`, "medium"));
      }
    }

    await Promise.all(writes);
  });

// ════════════════════════════════════════════════════════════════════════════
//  aggregateSessionOnEnd  (GATED — authoritative session aggregation)
// ════════════════════════════════════════════════════════════════════════════
exports.aggregateSessionOnEnd =
  onDocumentUpdated("translationSessions/{sessionId}", async (event) => {
    if (!SERVER_SIDE_ALERTS) return; // disabled by default

    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return;
    // Only run once, on the active → completed transition.
    if (before.status === after.status || after.status !== "completed") return;

    const sessionId = event.params.sessionId;
    const readings = await db.collection("gestureReadings")
        .where("sessionId", "==", sessionId).get();

    let sum = 0;
    const parts = [];
    readings.forEach((d) => {
      const r = d.data();
      sum += Number(r.confidenceScore || 0);
      if (r.detectedGesture) parts.push(r.detectedGesture);
    });
    const total = readings.size;

    await event.data.after.ref.update({
      totalGestures: total,
      averageConfidence: total ? sum / total : 0,
      translatedText: parts.join(" "),
    });
  });

// ── helpers ──────────────────────────────────────────────────────────────────
function createLog(uid, deviceId, deviceName, eventType, batteryLevel) {
  const ref = db.collection("connectionLogs").doc();
  return ref.set({
    logId: ref.id, userId: uid, deviceId, deviceName, eventType,
    timestamp: FieldValue.serverTimestamp(), batteryLevel, sessionId: null,
  });
}

function createAlert(uid, deviceId, alertType, title, message, severity) {
  const ref = db.collection("alerts").doc();
  return ref.set({
    alertId: ref.id, userId: uid, deviceId, alertType, title, message,
    severity, isRead: false, createdAt: FieldValue.serverTimestamp(),
  });
}
