# Contributing to Super Device Demo

First off, thank you for considering contributing to Super Device Demo! It's people like you that make this project a great tool for the OpenHarmony community.

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [How Can I Contribute?](#how-can-i-contribute)
3. [Development Setup](#development-setup)
4. [Coding Standards](#coding-standards)
5. [Commit Guidelines](#commit-guidelines)
6. [Pull Request Process](#pull-request-process)
7. [Reporting Bugs](#reporting-bugs)
8. [Suggesting Enhancements](#suggesting-enhancements)

## Code of Conduct

This project and everyone participating in it is governed by our commitment to foster an open and welcoming environment. By participating, you are expected to uphold this code.

### Our Standards

* Using welcoming and inclusive language
* Being respectful of differing viewpoints and experiences
* Gracefully accepting constructive criticism
* Focusing on what is best for the community
* Showing empathy towards other community members

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

* **Use a clear and descriptive title**
* **Describe the exact steps to reproduce the problem**
* **Provide specific examples to demonstrate the steps**
* **Describe the behavior you observed after following the steps**
* **Explain which behavior you expected to see instead and why**
* **Include screenshots if possible**
* **Include your environment details** (OS version, OpenHarmony version, device type)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

* **Use a clear and descriptive title**
* **Provide a step-by-step description of the suggested enhancement**
* **Provide specific examples to demonstrate the steps**
* **Describe the current behavior and explain the behavior you expected to see instead**
* **Explain why this enhancement would be useful**

### Pull Requests

* Fill in the required template
* Do not include issue numbers in the PR title
* Follow the [coding standards](#coding-standards)
* Include screenshots and animated GIFs in your pull request whenever possible
* End all files with a newline
* Avoid platform-dependent code

## Development Setup

### Prerequisites

* DevEco Studio 4.0 or higher
* OpenHarmony SDK API Level 11
* Full SDK installed
* Git

### Setup Steps

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/app-SuperDeviceDemo.git
   cd app-SuperDeviceDemo
   ```

3. Add the original repository as upstream:
   ```bash
   git remote add upstream https://github.com/imansmallapple/app-SuperDeviceDemo.git
   ```

4. Create a new branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

5. Open the project in DevEco Studio

6. Configure system-level application settings

7. Make your changes

## Coding Standards

### ArkTS/TypeScript Style Guide

* Use 2 spaces for indentation
* Use camelCase for variable and function names
* Use PascalCase for class names
* Use UPPER_CASE for constants
* Add JSDoc comments for public APIs
* Keep functions small and focused
* Write descriptive variable names

### Example

```typescript
/**
 * Manages device discovery and pairing operations
 */
export default class DeviceManager {
  private static readonly TAG: string = 'DeviceManager';
  private deviceList: deviceManager.DeviceBasicInfo[] = [];

  /**
   * Discovers nearby devices on the same network
   * @returns Promise<void>
   */
  public async discoverDevices(): Promise<void> {
    Log.info(DeviceManager.TAG, 'Starting device discovery');
    // Implementation
  }
}
```

### File Organization

* One component per file
* Group related functionality together
* Keep utility functions in separate files
* Use meaningful file names

### Comments

* Write comments for complex logic
* Keep comments up-to-date with code changes
* Use JSDoc for public APIs
* Avoid obvious comments

## Commit Guidelines

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

* **feat**: A new feature
* **fix**: A bug fix
* **docs**: Documentation only changes
* **style**: Changes that do not affect the meaning of the code
* **refactor**: A code change that neither fixes a bug nor adds a feature
* **perf**: A code change that improves performance
* **test**: Adding missing tests or correcting existing tests
* **chore**: Changes to the build process or auxiliary tools

### Examples

```
feat(device-manager): add support for device connection history

- Store pairing history in local storage
- Display previously paired devices
- Add option to quickly reconnect

Closes #123
```

```
fix(kv-store): resolve data sync issue on device disconnect

Fixed a race condition that caused data loss when device disconnected
during synchronization.

Fixes #456
```

## Pull Request Process

1. **Update Documentation**: Ensure any install or build dependencies are documented in the README.md

2. **Update Changelog**: Add your changes to CHANGELOG.md under the [Unreleased] section

3. **Test Your Changes**: 
   * Test on multiple devices if possible
   * Ensure no existing functionality is broken
   * Add new tests for new features

4. **Code Review**:
   * Address all review comments
   * Keep the discussion focused and professional
   * Be patient - maintainers may be busy

5. **Merge Requirements**:
   * At least one approval from a maintainer
   * All tests passing
   * No merge conflicts
   * Documentation updated

### PR Template

```markdown
## Description
Brief description of the changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
Describe the tests you ran and how to reproduce them

## Checklist
- [ ] My code follows the project's style guidelines
- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing unit tests pass locally with my changes
```

## Questions?

Feel free to open an issue with your question or contact the maintainers directly.

## Recognition

Contributors will be recognized in:
* The project README
* Release notes
* Special thanks in significant contributions

---

Thank you for contributing to Super Device Demo! 🎉
