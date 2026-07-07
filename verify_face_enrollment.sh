#!/bin/bash

# Verification Script for Face Enrollment Data
# This script helps verify that face enrollment data is being saved correctly

echo "========================================="
echo "🔍 Face Enrollment Data Verification"
echo "========================================="
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}This script will help you verify facial enrollment data in Firebase.${NC}"
echo ""
echo -e "${BLUE}To manually verify in Firebase Console:${NC}"
echo ""
echo "1. Open Firebase Console: https://console.firebase.google.com"
echo "2. Select your project"
echo "3. Go to Firestore Database"
echo "4. Look for 'FaceEnrollments' collection"
echo ""
echo -e "${GREEN}Expected Document Structure:${NC}"
echo "  Document ID: {eventId}-{userId}"
echo "  Example: GOAL-54D1-dbmeldgpzXgCU0cS9ZcHYsJ2Oxc2"
echo ""
echo "  Fields:"
echo "    - userId: (string) User's Firebase UID"
echo "    - userName: (string) User's display name"
echo "    - eventId: (string) Event ID"
echo "    - faceFeatures: (array) Facial feature data"
echo "    - sampleCount: (number) Should be 5"
echo "    - enrolledAt: (timestamp) When enrolled"
echo "    - version: (string) '1.0'"
echo ""
echo -e "${YELLOW}Watch Console Logs for These Messages:${NC}"
echo ""
echo "During Enrollment:"
echo "  ✓ 'Using logged-in user: Paul Reisinger (ID: dbmeldgpzXgCU0cS9ZcHYsJ2Oxc2)'"
echo "  ✓ 'Enrolling face for: userId=dbmeldgpzXgCU0cS9ZcHYsJ2Oxc2'"
echo "  ✓ '✅ Enrollment saved to Firestore: FaceEnrollments/GOAL-54D1-dbmeldgpzXgCU0cS9ZcHYsJ2Oxc2'"
echo ""
echo "During Scanner Check:"
echo "  ✓ 'Checking enrollment for: userId=dbmeldgpzXgCU0cS9ZcHYsJ2Oxc2'"
echo "  ✓ 'Looking for document: FaceEnrollments/GOAL-54D1-dbmeldgpzXgCU0cS9ZcHYsJ2Oxc2'"
echo "  ✓ 'Enrollment status for Paul Reisinger: true'"
echo ""
echo -e "${RED}If You See:${NC}"
echo "  ✗ 'Using test_user' ← WRONG! User not properly logged in"
echo "  ✗ 'Enrollment status: false' ← User ID mismatch"
echo ""
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${BLUE}Running app with filtered logging...${NC}"
echo ""

flutter run --verbose 2>&1 | grep -E "(Using logged-in user|Using guest user|Enrolling face for|Enrollment saved|Checking enrollment|Looking for document|Enrollment status)" --line-buffered
