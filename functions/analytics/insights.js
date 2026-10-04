"use strict";
const crypto = require("node:crypto");
const {onDocumentUpdated, onDocumentWritten} = require("firebase-functions/v2/firestore");
function analyzePeakHours(hourlySignIns) {
  if (!hourlySignIns || Object.keys(hourlySignIns).length === 0) {
    return {
      peakHour: null,
      peakCount: 0,
      recommendation: "Insufficient data for peak hour analysis",
      confidence: 0.0,
    };
  }

  const sortedHours = Object.entries(hourlySignIns)
      .sort((a, b) => a[0].localeCompare(b[0]));

  let peakHour = "";
  let peakCount = 0;
  let totalSignIns = 0;

  for (const [hour, count] of sortedHours) {
    const countNum = Number.isFinite(Number(count)) ? Math.max(0, Number(count)) : 0;
    totalSignIns += countNum;
    if (countNum > peakCount) {
      peakCount = countNum;
      peakHour = hour;
    }
  }

  const confidence = totalSignIns > 0 ? peakCount / totalSignIns : 0.0;

  let recommendation = "";
  if (peakHour) {
    const hour = parseInt(peakHour.split(":")[0]);
    if (hour >= 9 && hour <= 11) {
      recommendation = "Morning events (9-11 AM) show highest engagement. Consider scheduling future events during this time.";
    } else if (hour >= 12 && hour <= 14) {
      recommendation = "Lunch time (12-2 PM) is your peak period. Lunch-and-learn events could be highly successful.";
    } else if (hour >= 17 && hour <= 19) {
      recommendation = "Evening hours (5-7 PM) are most popular. After-work events align well with attendee preferences.";
    } else {
      recommendation = `Peak attendance at ${peakHour}. Consider this timing for future events.`;
    }
  }

  return {
    peakHour,
    peakCount,
    recommendation,
    confidence,
    totalSignIns,
    hourlyDistribution: hourlySignIns,
  };
}

/**
 * Analyze sentiment from comments
 */
function analyzeSentiment(comments) {
  if (!comments || comments.length === 0) {
    return {
      positiveRatio: 0.0,
      negativeRatio: 0.0,
      neutralRatio: 1.0,
      overallSentiment: "neutral",
      recommendation: "No comments available for sentiment analysis",
      confidence: 0.0,
    };
  }

  const positiveKeywords = [
    "great", "awesome", "amazing", "excellent", "fantastic", "wonderful",
    "good", "nice", "love", "enjoy", "happy", "satisfied", "impressed",
    "outstanding", "brilliant", "perfect", "best", "favorite", "recommend",
  ];

  const negativeKeywords = [
    "bad", "terrible", "awful", "horrible", "disappointing", "poor",
    "worst", "hate", "dislike", "boring", "waste", "useless", "frustrated",
    "angry", "annoyed", "confused", "difficult", "problem", "issue",
  ];

  let positiveCount = 0;
  let negativeCount = 0;
  let neutralCount = 0;

  for (const comment of comments) {
    const text = String(comment.comment || comment.text || "").toLowerCase();
    if (!text) continue;

    let positiveScore = 0;
    let negativeScore = 0;

    for (const keyword of positiveKeywords) {
      if (text.includes(keyword)) positiveScore++;
    }

    for (const keyword of negativeKeywords) {
      if (text.includes(keyword)) negativeScore++;
    }

    if (positiveScore > negativeScore) {
      positiveCount++;
    } else if (negativeScore > positiveScore) {
      negativeCount++;
    } else {
      neutralCount++;
    }
  }

  const total = positiveCount + negativeCount + neutralCount;
  const positiveRatio = total > 0 ? positiveCount / total : 0.0;
  const negativeRatio = total > 0 ? negativeCount / total : 0.0;
  const neutralRatio = total > 0 ? neutralCount / total : 0.0;

  let overallSentiment = "neutral";
  if (positiveRatio > 0.6) {
    overallSentiment = "positive";
  } else if (negativeRatio > 0.6) {
    overallSentiment = "negative";
  }

  let recommendation = "";
  if (overallSentiment === "positive") {
    recommendation = "Excellent feedback! Attendees are highly satisfied. Consider expanding similar event formats.";
  } else if (overallSentiment === "negative") {
    recommendation = "Address attendee concerns. Consider gathering more detailed feedback to improve future events.";
  } else {
    recommendation = "Mixed feedback received. Consider implementing feedback surveys to better understand attendee needs.";
  }

  return {
    positiveRatio,
    negativeRatio,
    neutralRatio,
    overallSentiment,
    recommendation,
    confidence: 0.0,
    totalComments: total,
    positiveCount,
    negativeCount,
    neutralCount,
  };
}

/**
 * Generate optimization predictions
 */
function generateOptimizations(analyticsData, peakHoursAnalysis, sentimentAnalysis) {
  const optimizations = [];

  const totalAttendees = analyticsData.totalAttendees || 0;
  const dropoutRate = analyticsData.dropoutRate || 0.0;
  const repeatAttendees = analyticsData.repeatAttendees || 0;

  // Peak hours optimization
  if (peakHoursAnalysis.peakHour) {
    const hour = parseInt(peakHoursAnalysis.peakHour.split(":")[0]);

    if (hour >= 9 && hour <= 11) {
      optimizations.push({
        type: "timing",
        title: "Optimize Event Timing",
        description: "Compare future morning schedules with the observed attendance pattern",
        impact: "High",
        confidence: peakHoursAnalysis.confidence || 0.0,
        implementation: "Schedule future events during peak morning hours",
      });
    } else if (hour >= 17 && hour <= 19) {
      optimizations.push({
        type: "timing",
        title: "Evening Event Strategy",
        description: "Compare future evening schedules with the observed attendance pattern",
        impact: "Medium",
        confidence: peakHoursAnalysis.confidence || 0.0,
        implementation: "Focus on after-work events and networking sessions",
      });
    }
  }

  // Weekend optimization
  if (totalAttendees > 0) {
    optimizations.push({
      type: "scheduling",
      title: "Weekend Events",
      description: "Consider testing a weekend schedule and comparing actual attendance",
      impact: "High",
      confidence: 0.0,
      implementation: "Schedule events on Saturdays or Sundays",
    });
  }

  // Dropout rate optimization
  if (dropoutRate > 20) {
    optimizations.push({
      type: "engagement",
      title: "Reduce Dropout Rate",
      description: "Consider reminders and measure whether attendance changes",
      impact: "Medium",
      confidence: 0.0,
      implementation: "Send email and in-app reminders 24h and 1h before events",
    });
  }

  // Repeat attendee optimization
  if (repeatAttendees > 0 && totalAttendees > 0) {
    const repeatRate = (repeatAttendees / totalAttendees) * 100;
    if (repeatRate < 30) {
      optimizations.push({
        type: "retention",
        title: "Increase Repeat Attendance",
        description: "Consider member benefits and measure repeat attendance",
        impact: "High",
        confidence: 0.0,
        implementation: "Create member benefits and early access programs",
      });
    }
  }

  // Sentiment-based optimizations
  if (sentimentAnalysis.overallSentiment === "negative") {
    optimizations.push({
      type: "feedback",
      title: "Improve Event Quality",
      description: "Review attendee feedback and measure satisfaction after changes",
      impact: "High",
      confidence: 0.0,
      implementation: "Conduct post-event surveys and implement feedback",
    });
  }

  return optimizations.map((item) => ({...item, confidence: null, confidenceAvailable: false}));
}

/**
 * Analyze dropout patterns
 */
function analyzeDropoutPatterns(analyticsData) {
  const dropoutRate = analyticsData.dropoutRate || 0.0;
  const totalAttendees = analyticsData.totalAttendees || 0;

  let recommendation = "";
  if (dropoutRate > 50) {
    recommendation = "High dropout rate detected. Consider improving event marketing and reminder systems.";
  } else if (dropoutRate > 25) {
    recommendation = "Moderate dropout rate. Implement better engagement strategies.";
  } else {
    recommendation = "Low dropout rate. Your event planning is effective!";
  }

  return {
    dropoutRate,
    recommendation,
    severity: dropoutRate > 50 ? "High" : dropoutRate > 25 ? "Medium" : "Low",
    totalAttendees,
    confidence: 0.0,
  };
}

/**
 * Analyze repeat attendee patterns
 */
function analyzeRepeatAttendees(analyticsData) {
  const repeatAttendees = analyticsData.repeatAttendees || 0;
  const totalAttendees = analyticsData.totalAttendees || 0;

  const repeatRate = totalAttendees > 0 ? (repeatAttendees / totalAttendees) * 100 : 0.0;

  let recommendation = "";
  if (repeatRate > 50) {
    recommendation = "Excellent repeat attendance! Your events have strong community building.";
  } else if (repeatRate > 25) {
    recommendation = "Good repeat attendance. Consider loyalty programs to increase retention.";
  } else {
    recommendation = "Low repeat attendance. Focus on building community and improving event quality.";
  }

  return {
    repeatRate,
    repeatAttendees,
    totalAttendees,
    recommendation,
    confidence: 0.0,
  };
}

function createInsightsHandler(admin) {
  const db = admin.firestore();
  return async (event) => {
    const eventId = event.params.docId;
    const ref = db.collection("ai_insights").doc(eventId);
    return db.runTransaction(async (tx) => {
      const [current, analytics, previous] = await Promise.all([tx.get(db.collection("Events").doc(eventId)),
        tx.get(db.collection("event_analytics").doc(eventId)), tx.get(ref)]);
      const deleting = current.exists && current.get("customerUid") ?
        await tx.get(db.collection("account_deletion_jobs").doc(current.get("customerUid"))) : null;
      if (!current.exists || !analytics.exists || deleting?.exists) {
        if (previous.exists) tx.delete(ref);
        return {removed: previous.exists};
      }
      const data = analytics.data();
      const summaries = Array.isArray(data.feedbackAnalytics?.commentSummaries) ? data.feedbackAnalytics.commentSummaries.slice(0, 10) : [];
      const inputs = {hourlySignIns: data.hourlySignIns || {}, totalAttendees: data.totalAttendees || 0,
        dropoutRate: data.dropoutRate || 0, repeatAttendees: data.repeatAttendees || 0, comments: summaries};
      const fingerprint = crypto.createHash("sha256").update(JSON.stringify(inputs)).digest("hex");
      if (previous.get("sourceFingerprint") === fingerprint) return {replayed: true};
      const peakHoursAnalysis = analyzePeakHours(inputs.hourlySignIns);
      const sentimentAnalysis = {...analyzeSentiment(summaries.map((comment) => ({comment}))), confidence: null, confidenceAvailable: false};
      tx.set(ref, {peakHoursAnalysis, sentimentAnalysis,
        optimizationPredictions: generateOptimizations(inputs, peakHoursAnalysis, sentimentAnalysis),
        dropoutAnalysis: {...analyzeDropoutPatterns(inputs), confidence: null, confidenceAvailable: false},
        repeatAttendeeAnalysis: {...analyzeRepeatAttendees(inputs), confidence: null, confidenceAvailable: false},
        method: "descriptive_heuristics", isPredictiveModel: false, feedbackSampleSize: summaries.length,
        sourceFingerprint: fingerprint, lastUpdated: admin.firestore.FieldValue.serverTimestamp()});
      return {updated: true};
    });
  };
}
function createLoggedInsightsHandler(admin, triggerName) {
  const handle = createInsightsHandler(admin);
  return async (event) => {
    const result = await handle(event);
    require("firebase-functions/logger").info("Analytics insight delivery completed", {
      eventId: event.params.docId, deliveryId: event.id || null, triggerName,
      sourceVersion: event.data?.after?.updateTime?.toDate?.().toISOString() || null,
      outcome: result.updated ? "updated" : result.replayed ? "replayed" : result.removed ? "removed" : "unchanged_absent",
    });
    return result;
  };
}
function createTriggerAIInsights(admin) {
  // Keep the deployed event type stable during migration. Updating an existing
  // function from updated to written cannot be performed as an in-place deploy.
  return onDocumentUpdated({document: "event_analytics/{docId}", region: "us-central1", retry: true}, createLoggedInsightsHandler(admin, "triggerAIInsights"));
}
function createTriggerAIInsightsV2(admin) {
  return onDocumentWritten({document: "event_analytics/{docId}", region: "us-central1", retry: true}, createLoggedInsightsHandler(admin, "triggerAIInsightsV2"));
}
module.exports = {createTriggerAIInsights, createTriggerAIInsightsV2, createInsightsHandler, analyzePeakHours, analyzeSentiment, generateOptimizations};
