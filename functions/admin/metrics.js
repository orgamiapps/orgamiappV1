'use strict';

const {onSchedule} = require('firebase-functions/v2/scheduler');

function createMetricsAggregator(adminSdk) {
  const db = adminSdk.firestore();
  return onSchedule({region: 'us-central1', schedule: '15 2 * * *', timeZone: 'UTC', timeoutSeconds: 540, memory: '1GiB'}, async () => {
    const today = new Date().toISOString().slice(0, 10);
    const [users, events, attendance, groups, reports, basic, premium] = await Promise.all([
      db.collection('Customers').count().get(), db.collection('Events').count().get(), db.collection('Attendance').count().get(), db.collection('Organizations').count().get(), db.collection('reports').where('status', '==', 'open').count().get(), db.collection('subscriptions').where('tier', '==', 'basic').where('status', '==', 'active').count().get(), db.collection('subscriptions').where('tier', '==', 'premium').where('status', '==', 'active').count().get(),
    ]);
    const metrics = {usersTotal: users.data().count, eventsTotal: events.data().count, registrationsTotal: attendance.data().count, groupsTotal: groups.data().count, openReports: reports.data().count, activeBasic: basic.data().count, activePremium: premium.data().count, updatedAt: adminSdk.firestore.FieldValue.serverTimestamp(), metricsVersion: 1};
    await Promise.all([db.collection('admin_metrics_current').doc('current').set(metrics), db.collection('admin_metrics_daily').doc(today).set(metrics)]);
  });
}

module.exports = {createMetricsAggregator};
