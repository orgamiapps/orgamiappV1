#!/bin/bash

# Face Enrollment Testing Script
# This script helps test the new face enrollment implementation

echo "========================================="
echo "Face Enrollment Testing Script"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Preparing to test face enrollment...${NC}"
echo ""

# Step 1: Clean and rebuild
echo -e "${BLUE}Step 1: Cleaning build...${NC}"
flutter clean

echo ""
echo -e "${BLUE}Step 2: Getting dependencies...${NC}"
flutter pub get

echo ""
echo -e "${GREEN}=== TESTING OPTIONS ===${NC}"
echo ""
echo "The new face enrollment has THREE test modes:"
echo ""
echo -e "${GREEN}1. REAL MODE${NC} - Uses actual camera and face detection"
echo -e "${YELLOW}2. SIMULATION MODE${NC} - Auto-completes without real detection"  
echo -e "${BLUE}3. GUEST MODE${NC} - Tests guest user enrollment"
echo ""
echo -e "${GREEN}Debug Panel Features:${NC}"
echo "• Real-time state display"
echo "• Frame counter"
echo "• Face detection stats"
echo "• Error messages"
echo "• Elapsed time"
echo ""
echo -e "${YELLOW}To test, navigate to:${NC}"
echo "1. Any event in the app"
echo "2. Select 'Location & Facial Recognition'"
echo "3. The new enrollment screen will appear"
echo ""
echo -e "${GREEN}Or use the test screen by adding this route:${NC}"
echo "TestFaceEnrollmentScreen()"
echo ""
echo "========================================="
echo ""
echo -e "${GREEN}Starting app with verbose logging...${NC}"
echo -e "${YELLOW}Watch for these log messages:${NC}"
echo ""
echo "✓ 'SimpleFaceEnrollmentScreen: initState called'"
echo "✓ 'State changed to: READY'"
echo "✓ 'Captured X of 5 samples'"
echo "✓ 'Enrollment completed successfully'"
echo ""
echo "========================================="

# Run the app with filtered logging
flutter run --verbose 2>&1 | grep -E "(SimpleFaceEnrollment|State changed|Captured|sample|face|Face|enrollment|Enrollment|SIMULATION)" --line-buffered
