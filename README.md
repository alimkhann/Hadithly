# Hadithly 📱

A modern, multi-language Hadith reader app designed specifically for Russian-speaking Muslims, with support for English, Arabic, and Russian translations.

## 🌟 Features

### ✅ Phase 1: Foundation (Completed)
- **Multi-language Support**: English, Arabic, and Russian UI and content
- **Modern Architecture**: MVVM pattern with SwiftUI and SwiftData
- **Theme Support**: Light, Dark, and System themes
- **RTL Layout**: Full right-to-left support for Arabic
- **Localization**: Comprehensive Russian and English localization
- **Offline Support**: Local data persistence with SwiftData
- **Accessibility**: VoiceOver and Dynamic Type support

### 🔄 Phase 2: Core Features (In Progress)
- **API Integration**: Connect to multiple Hadith APIs
- **Search Functionality**: Cross-language search with filters
- **Reading Experience**: Enhanced multi-language display
- **Navigation**: Improved tab-based interface

### ⏳ Phase 3: Advanced Features (Planned)
- **Save & Organize**: Custom folders for saved hadiths
- **Export/Import**: JSON-based data backup
- **Daily Notifications**: Random hadith notifications
- **Holiday Features**: Special hadiths for Islamic holidays

### ⏳ Phase 4: Polish & Widgets (Planned)
- **iOS Widgets**: Home screen widgets
- **UI Polish**: Modern, accessible design
- **Performance**: Efficient caching and optimization

## 🏗️ Architecture

### MVVM Pattern
- **Models**: `Hadith`, `UserFolder`, `AppSettings`
- **ViewModels**: Separate ViewModels for each major view
- **Views**: SwiftUI views with proper separation of concerns

### Data Layer
- **SwiftData**: Modern persistence framework
- **Service Protocols**: SOLID principles for testability
- **Caching**: NSCache for performance optimization

### Network Layer
- **API Services**: Multiple Hadith API integration
- **Error Handling**: Graceful degradation and retry logic
- **Offline Support**: Local data persistence

## 📱 Screenshots

*Screenshots will be added as the app progresses*

## 🚀 Getting Started

### Prerequisites
- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/alimkhann/Hadithly.git
   cd Hadithly
   ```

2. **Open in Xcode**
   ```bash
   open Hadithly.xcodeproj
   ```

3. **Build and Run**
   - Select your target device or simulator
   - Press `Cmd + R` to build and run

### Project Structure

```
Hadithly/
├── Sources/
│   ├── App/
│   │   ├── HadithlyApp.swift
│   │   └── ContentView.swift
│   ├── Models/
│   │   ├── Hadith.swift
│   │   ├── SwiftDataModels.swift
│   │   └── UserFolder.swift
│   ├── Services/
│   │   ├── Network/
│   │   │   └── HadithAPIService.swift
│   │   ├── Persistence/
│   │   │   ├── LocalStorageService.swift
│   │   │   └── PersistenceController.swift
│   │   └── NotificationService.swift
│   ├── Utilities/
│   │   ├── LocalizationManager.swift
│   │   └── ThemeManager.swift
│   └── Views/
│       ├── Home/
│       │   ├── HomeView.swift
│       │   └── HomeViewModel.swift
│       ├── Search/
│       │   ├── SearchView.swift
│       │   └── SearchViewModel.swift
│       ├── Library/
│       │   ├── LibraryView.swift
│       │   └── LibraryViewModel.swift
│       ├── Settings/
│       │   ├── SettingsView.swift
│       │   └── SettingsViewModel.swift
│       └── HadithDetail/
│           ├── HadithDetailView.swift
│           └── HadithDetailViewModel.swift
└── Resources/
    └── Assets.xcassets/
```

## 🎯 Key Features

### Multi-language Support
- **UI Languages**: English, Russian, Arabic
- **Content Languages**: English, Arabic, Russian translations
- **Dynamic Switching**: Real-time language switching
- **RTL Support**: Full right-to-left layout for Arabic

### Modern UI/UX
- **SwiftUI**: Native iOS design language
- **Theme Support**: Light, Dark, and System themes
- **Accessibility**: VoiceOver and Dynamic Type support
- **Responsive Design**: Adapts to different screen sizes

### Data Management
- **SwiftData**: Modern persistence framework
- **Offline Support**: Works without internet connection
- **Export/Import**: JSON-based data backup (planned)
- **Caching**: Efficient data caching for performance

## 🔧 Development

### Architecture Principles
- **SOLID**: Single responsibility, open/closed, etc.
- **DRY**: Don't repeat yourself
- **KISS**: Keep it simple, stupid
- **MVVM**: Model-View-ViewModel pattern

### Code Style
- **SwiftUI**: Modern declarative UI
- **Async/Await**: Modern concurrency
- **Protocol-Oriented**: Swift best practices
- **Documentation**: Comprehensive code comments

### Testing
- **Unit Tests**: ViewModels and Services
- **UI Tests**: User interface testing
- **Integration Tests**: API and persistence testing

## 📊 Progress

### Phase 1: Foundation ✅
- [x] MVVM Architecture
- [x] SwiftData Integration
- [x] Multi-language Support
- [x] Theme Switching
- [x] RTL Layout Support
- [x] Localization System
- [x] Basic UI Navigation

### Phase 2: Core Features 🔄
- [ ] API Integration
- [ ] Search Functionality
- [ ] Enhanced Reading Experience
- [ ] Improved Navigation

### Phase 3: Advanced Features ⏳
- [ ] Save & Organize
- [ ] Export/Import
- [ ] Daily Notifications
- [ ] Holiday Features

### Phase 4: Polish & Widgets ⏳
- [ ] iOS Widgets
- [ ] UI Polish
- [ ] Performance Optimization

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Setup
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Hadith APIs**: [fawazahmed0/hadith-api](https://github.com/fawazahmed0/hadith-api), [HadithAPI.com](https://hadithapi.com)
- **SwiftUI**: Apple's modern UI framework
- **SwiftData**: Apple's modern persistence framework
- **Community**: All contributors and supporters

## 📞 Contact

- **GitHub**: [@alimkhann](https://github.com/alimkhann)
- **Repository**: [Hadithly](https://github.com/alimkhann/Hadithly)

## 🎉 Support

If you find this project helpful, please consider:
- ⭐ Starring the repository
- 🐛 Reporting bugs
- 💡 Suggesting features
- 🤝 Contributing code

---

**Made with ❤️ for the Muslim community**
