'use strict';
const {PLAN_PRICE_ENV} = require('./constants');
function planForPrice(priceId, environment, fallback = null) { return Object.keys(PLAN_PRICE_ENV).find((plan) => environment[PLAN_PRICE_ENV[plan]] === priceId) || fallback; }
function tierForPlan(planId) { return planId?.startsWith('premium_') ? 'premium' : planId?.startsWith('basic_') ? 'basic' : 'free'; }
module.exports = {planForPrice, tierForPlan};
