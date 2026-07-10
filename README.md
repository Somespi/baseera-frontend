![logo](./resources/logo.png)

Baseera is a Flutter-based mobile application designed primarily for accessibility and assistance to visually impaired users and their helpers. The app offers multiple features including document scanning (OCR), maps with saved locations, Bluetooth device integration, speech recognition, and text-to-speech functionality with a focus on Arabic language support. (the backend-end repo may be found [](https://github.com/Somespi/baseera-backend)).

## Features

- **User Roles**: Allows users to select their category as either visually impaired ("كفيف") or assistant ("مُساعد") (incomplete).
- **Document Scanning (OCR)**: Extracts text from images to assist with reading.
- **Maps & Location Management**: Add, view, and delete saved locations with Arabic labels.
- **Bluetooth Integration**: Communicates with assistive Bluetooth devices (e.g., braille devices, motion sensors).
- **Speech to Text & Text to Speech**: Converts speech to text commands and reads out information.
- **Movement Detection**: Uses gyroscope sensors to detect user motion.
- **Multi-language Support**: Supports right-to-left (RTL) Arabic UI and fonts using Google Fonts.
- **Taxi Assistance**: Provides functionality related to taxi services for visually impaired users (incomplete).


## Getting Started

### Prerequisites

- Flutter SDK installed (latest stable version)
- Dart SDK
- An Android or iOS device/emulator
- Bluetooth enabled device for assistive functionalities

### Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/Somespi/baseera-frontend.git
   cd baseera-frontend
   ```

2. Install dependencies:

   ```bash
   flutter pub get
   ```

3. Run the app:

   ```bash
   flutter run
   ```


## Project Structure

- `lib/main.dart` - Entry point of the app, initializes services like text-to-speech, speech-to-text, and gyroscope monitoring, and controls the main navigation and UI state.
- `lib/pages/` - Contains separate Flutter widgets for different app pages:
  - `login_route.dart` - Login page where users select their user role and enter credentials.
  - `maps_route.dart` - Page to add and manage saved map locations.
  - `ocr_route.dart` - Handles document scanning and OCR features.
- `lib/services/` - Core services that handle device Bluetooth connections, map management, speech recognition, text-to-speech, data processing (tfidf), and Uber service related logic.
- `assets/icons/` - Icon assets for the UI such as blind and assistive user icons.

## Usage

1. Use the bottom navigation bar to switch between the home page, documents (OCR), and maps.
2. In the Maps section, add new locations by entering the name and related terms in Arabic, view saved locations, or delete unwanted entries.
3. Scan documents using the OCR feature to extract text.
4. Connect and interact with Bluetooth assistive devices configured within the app.
5. The app also listens to speech input and can respond or read out information accordingly.

## Permissions

The app requires the following permissions:

- Location access for maps and location services.
- Bluetooth access to connect to assistive devices.
- Microphone access for speech-to-text.


## Technologies and Libraries

- Flutter & Dart
- bluetooth: `flutter_blue_plus`
- Geolocation & Geocoding
- Google Fonts (Changa, Cairo, Rubik)
- Image processing (image package)
- Speech to Text & Text to Speech services
- HTTP networking (http package)
- Permission handling
- Sensors (gyroscope)



## License

The project is licensed under PolyForm Noncommercial License 1.0.0.



## Contact

For questions or support, please open an issue on the GitHub repository.
