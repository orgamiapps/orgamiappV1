'use strict';

const ROLES = Object.freeze(['super_admin', 'support', 'billing_admin', 'analyst', 'moderator']);

const ROLE_PERMISSIONS = Object.freeze({
  super_admin: ['*'],
  support: ['accounts.read', 'accounts.mutate', 'audit.read'],
  billing_admin: ['accounts.read', 'subscriptions.read', 'subscriptions.mutate', 'audit.read'],
  analyst: ['analytics.read', 'accounts.read', 'subscriptions.read', 'audit.read'],
  moderator: ['moderation.read', 'moderation.mutate', 'events.read', 'events.mutate', 'organizations.read', 'organizations.mutate', 'audit.read'],
});

const PLAN_PRICE_ENV = Object.freeze({
  basic_monthly: 'STRIPE_PRICE_BASIC_MONTHLY',
  basic_6month: 'STRIPE_PRICE_BASIC_SIX_MONTH',
  basic_yearly: 'STRIPE_PRICE_BASIC_YEARLY',
  premium_monthly: 'STRIPE_PRICE_PREMIUM_MONTHLY',
  premium_6month: 'STRIPE_PRICE_PREMIUM_SIX_MONTH',
  premium_yearly: 'STRIPE_PRICE_PREMIUM_YEARLY',
});

module.exports = {ROLES, ROLE_PERMISSIONS, PLAN_PRICE_ENV};
