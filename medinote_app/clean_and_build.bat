@echo off
echo Cleaning and rebuilding MediNote Flutter App...
echo.

echo Step 1: Cleaning Flutter project...
flutter clean

echo.
echo Step 2: Getting Flutter dependencies...
flutter pub get

echo.
echo Step 3: Cleaning Android build...
cd android
gradlew clean
cd ..

echo.
echo Step 4: Building Flutter app...
flutter build apk --debug

echo.
echo Build completed! Check for any errors above.
pause
