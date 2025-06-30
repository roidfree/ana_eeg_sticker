# ANA - EEG Focus Monitor

A Flutter app that connects to state-of-the-art biosignal patch via Bluetooth to monitor focus, stress, and mental state in real-time.

## 🧠 What is ANA?

ANA is a wireless EEG monitoring system that turns brain activity into actionable insights. Think of it as a fitness tracker for your mind - it measures focus levels, stress, and mental fatigue to help you optimize your cognitive performance.

## 📱 Features

- **Real-time EEG monitoring** via Bluetooth Low Energy
- **Live focus tracking** with visual feedback
- **Stress level detection** using brain wave analysis
- **Session recording** and playback
- **Clean, intuitive interface** designed for daily use

## 🚀 Quick Start

### Prerequisites
- Flutter SDK (3.16+)
- Android Studio or Xcode
- Compatible EEG device (OpenBCI Cyton, nRF52832 prototype)

### Installation
```bash
# Clone the repository
git clone https://github.com/your-username/ana-app.git
cd ana_eeg_sticker

# Install dependencies
flutter pub get

# Run the app
flutter run
```

## 📦 Dependencies

```yaml
dependencies:
  flutter_blue_plus: ^1.12.0  # BLE connectivity
  fl_chart: ^0.65.0           # Real-time charts
  riverpod: ^2.4.0            # State management
  hive: ^2.2.3                # Local storage
```

## 🔧 Usage

1. **Connect Device**: Turn on your EEG device and tap "Scan" in the app
2. **Start Session**: Once connected, press "Start Monitoring" 
3. **View Live Data**: Watch your brain waves and focus metrics in real-time
4. **Review Sessions**: Check your focus patterns and improvements over time

## 📊 How It Works

```
EEG Sensor → Bluetooth → Signal Processing → Algorithms (e.g Focus) → Live Display
```

The app does things like: filter EEG signals (1-40 Hz), extracts alpha and beta wave features, and calculates a real-time focus score based on established neuroscience research.

## 🧪 Signal Processing

- **Bandpass filtering**: Removes noise and isolates brain waves
- **Feature extraction**: Alpha (8-12 Hz) and Beta (13-30 Hz) power
- **Focus metric**: Alpha/Beta ratio with smoothing algorithm
- **Real-time processing**: <100ms latency for immediate feedback

## 🛠️ Development

### Project Structure
```
lib/
├── main.dart              # App entry point
├── models/                # Data structures
├── services/              # BLE and signal processing
├── screens/               # UI screens
└── widgets/               # Reusable components
```

### Running Tests
```bash
flutter test
```

### Building for Release
```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

## 📱 Screenshots

[Add screenshots of your app here]

## 🎯 Roadmap

- [x] BLE connectivity
- [x] Real-time EEG display
- [x] Basic focus metrics
- [ ] Advanced signal processing
- [ ] Cloud data sync
- [ ] Multi-device support
- [ ] Meditation guidance

## 🤝 Contributing

We're a small team building this in the open. Feel free to:
- Report bugs via GitHub Issues
- Suggest features
- Submit pull requests

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🔗 Hardware Compatibility

**Tested Devices:**
- OpenBCI Cyton Board
- Custom nRF52832 prototype

**BLE Requirements:**
- Bluetooth 4.0+
- Custom EEG data characteristic
- Sampling rate: 250+ Hz

## 📧 Contact

For questions about the project or collaboration opportunities, create an issue or reach out via GitHub.

---

**Built with ❤️ for better brain health and cognitive performance.**