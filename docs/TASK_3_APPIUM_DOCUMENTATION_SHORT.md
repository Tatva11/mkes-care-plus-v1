# DevOps SLA Assignment — Task 3: Mobile Application Testing
## Practical Implementation: Mobile UI Testing and Automation with Appium, UiAutomator2, and Appium Inspector

---

| **Academic Information** | **Details** |
| :--- | :--- |
| **Course / Subject** | DevOps SLA (Software Lifecycle Automation) |
| **Assignment Task** | **Task 3: Mobile Application Testing using Appium** |
| **Application Under Test** | MKES CARE+ Clinical Management Platform (Flutter Mobile Android) |
| **Device / Platform** | Physical Android Smartphone, Model: A142 (CPH2359 series), Android 16 (API 36) |
| **Connection Interface** | Android Debug Bridge (ADB) v1.0.41 over USB Debugging (Device ID: `000703458000429`) |
| **Automation Stack** | Appium Server v3.8.0, UiAutomator2 Driver v8.7.0, Appium Inspector GUI |

---

## 1. Objective

Demonstrate mobile application UI testing, interactive element inspection, and functional test verification for the **MKES CARE+** Flutter application deployed on a physical Android device (model reported as A142, Android 16) using **Appium Server v3.8.0**, the **UiAutomator2** automation driver, and **Appium Inspector**. The practical implementation validates Android Debug Bridge (ADB) device attachment, W3C WebDriver session establishment, accessibility DOM tree parsing, client-side input validation guardrails, and live authenticated clinical navigation across Supabase-backed patient records.

---

## 2. Tools and Environment

- **Host Workstation:** Windows 11 Pro (64-bit) with PowerShell 7 and Node.js LTS runtime environment.
- **Target Physical Device:** Android Smartphone (Device ID: `000703458000429`, Model reported as A142 / CPH2359 series), running Android 16 (API 36).
- **Bridge Connection:** Android Debug Bridge (ADB) version 1.0.41 over USB debugging interface.
- **Automation Server:** Appium Server v3.8.0 listening on `http://127.0.0.1:4723` (autodetected path: `C:\Users\Tatva jain\.appium`).
- **Mobile Automation Driver:** `appium-uiautomator2-driver` v8.7.0 providing direct Google UiAutomator2 test daemon integration.
- **UI Inspection Tool:** Appium Inspector (Desktop GUI) for live screen mirroring, XPath generation, and coordinate resolution.
- **Application Under Test (AUT):** MKES CARE+ Flutter Mobile App (Package: `com.example.mkes_care`, Main Activity: `com.example.mkes_care.MainActivity`).
- **Automated Test Client:** Python `Appium-Python-Client` test suite (`D:\mkes-lovable\mobile_tests\test_mkes_app.py`).
- **Backend Cloud Persistence:** Supabase PostgreSQL cloud instance connected over outbound client HTTPS/REST.

---

## 3. Practical Steps & Implementation

### Step 1: Connecting Physical Android Device via ADB

The physical Android device (model A142) was configured with **Developer Options** and **USB Debugging** enabled. The connection was verified via PowerShell using the Android Debug Bridge (ADB):

```powershell
PS C:\Users\Tatva jain> adb devices
List of devices attached
000703458000429 device
```

![Figure 1 — Android Debug Bridge (ADB): Physical Android Device Attached and Authorized](assets/appium_fig2_adb_device_connected.png)
*Figure 1 — Android Debug Bridge (ADB): Physical Android Device Attached and Authorized ('000703458000429 device')*

> **[Verification]** Confirms ADB daemon actively communicating with the authorized physical device (model A142) over USB, establishing the physical transport layer for UiAutomator2 test execution.

---

### Step 2: Starting Appium Server with UiAutomator2 Driver

Appium Server v3.8.0 was launched from the command line in PowerShell. During startup, Appium dynamically loaded the UiAutomator2 driver (`uiautomator2@8.7.0` in 2.951s) and bound its W3C-compliant REST HTTP listener to port 4723:

```powershell
PS C:\Users\Tatva jain> appium
[Appium] Welcome to Appium v3.8.0
[Appium] The autodetected Appium home path: C:\Users\Tatva jain\.appium
[Appium] Attempting to load driver uiautomator2...
[Appium] Requiring driver at C:\Users\Tatva jain\.appium\node_modules\appium-uiautomator2-driver\build\lib\index.js
[Appium] AndroidUiautomator2Driver has been successfully loaded in 2.951s
[Appium] Appium REST http interface listener started on http://0.0.0.0:4723
[Appium] You can provide the following URLs in your client code to connect to this server:
  http://172.19.16.1:4723/
  http://10.110.2.112:4723/
  http://127.0.0.1:4723/ (only accessible from the same host)
[Appium] Available drivers:
[Appium]   - uiautomator2@8.7.0 (automationName 'UiAutomator2')
[HTTP] --> POST /session {"capabilities":{"alwaysMatch":{"platformName":"Android","appium:automationName":"UiAutomator2","appium:deviceName":"A142","appium:udid":"YOUR_NEW_DEVICE_ID","appium:noReset":true,...}}}
```

![Figure 2 — Appium Server v3.8.0: Active REST HTTP Listener on Port 4723](assets/appium_fig1_server_running.png)
*Figure 2 — Appium Server v3.8.0: Active REST HTTP Listener on Port 4723 and UiAutomator2 Driver Loading*

> **[Verification]** Validates Appium server initialization, UiAutomator2 driver registration, and live receipt of incoming W3C WebDriver session creation requests targeting device 'A142'.

---

### Step 3: Appium Inspector Session Setup & Capabilities Handshake

Appium Inspector was configured with W3C Desired Capabilities to attach to the running MKES CARE+ Flutter application:

```json
{
  "platformName": "Android",
  "appium:automationName": "UiAutomator2",
  "appium:deviceName": "A142",
  "appium:udid": "000703458000429",
  "appium:appPackage": "com.example.mkes_care",
  "appium:appActivity": "com.example.mkes_care.MainActivity",
  "appium:noReset": true,
  "appium:newCommandTimeout": 3600
}
```

Upon session initiation, Appium deployed the lightweight UiAutomator2 server instrumentation package to the device, hooked into the Android Accessibility Framework, and generated the initial XML DOM hierarchy:

![Figure 3 — Appium Inspector Session: Live Screen Mirroring and Root DOM Hierarchy](assets/appium_fig3_inspector_session_launch.png)
*Figure 3 — Appium Inspector Session: Live Screen Mirroring and Root DOM Hierarchy of MKES CARE+*

> **[Verification]** Proves active inspection session connected to `com.example.mkes_care`, displaying the live Role Selection screen and root FrameLayout bounds `[0,0][1084,2412]`.

---

### Step 4: Mobile UI Hierarchy Inspection & Locator Strategy

In Flutter applications, UI elements are rendered via an internal canvas engine rather than native Android View classes. Flutter bridges accessibility metadata via Semantics nodes. Appium Inspector allows testers to inspect these elements and derive robust locators:

- **Target Element:** "Admin Portal" selection card (*For clinic administrators, doctors, and department heads*).
- **Android UiAutomator Selector:** `new UiSelector().description("Admin Portal\nFor clinic administrators...")`
- **XPath Selector:** `//android.view.View[contains(@content-desc, 'Admin Portal')]`
- **Box Model & Pixel Coordinates:** Bounds `(38, 1072)` to `(1047, 1349)` — Dimensions: 1009 px width × 277 px height.
- **Element Attributes:** `package="com.example.mkes_care"`, `class="android.widget.Button"`, `clickable="false"`, `displayed="true"`.

![Figure 4 — UI Element Inspection: Inspecting 'Admin Portal' Button and Locators](assets/appium_fig4_ui_hierarchy_inspection.png)
*Figure 4 — UI Element Inspection: Inspecting 'Admin Portal' Button, Bounding Box (1009×277 px), and Locators*

> **[Verification]** Demonstrates precise element selection, attribute extraction, and bounding box coordinates within Appium Inspector for automated script generation.

---

### Step 5: Functional Test Execution — Login Input Validation

A critical UI validation test was conducted on the **Administrator Sign In** screen to verify client-side security guardrails. A valid email syntax (`tatvajain110907@gmail.com`) was entered alongside an insufficient password of 5 characters (`.....`). The Flutter Form validator immediately flagged the input, displaying an inline validation error:

> **[Validation Error Triggered]**  
> Error Banner: **"Password must be at least 6 characters."** Form submission is blocked locally, preventing unauthorized or malformed authentication payloads from reaching the backend.

![Figure 5 — Form Validation Test: Live Inline Error on Admin Sign In](assets/appium_fig5_login_validation_error.png)
*Figure 5 — Form Validation Test: Live Inline Error ('Password must be at least 6 characters') on Admin Sign In*

> **[Verification]** Validates client-side validation logic rejecting short passwords (< 6 characters) on Administrator Sign In screen prior to network transit.

> [!WARNING]
> **[Evidence Transparency Note]**  
> A dedicated screenshot showing empty-login submission (submitting with zero characters) was not separately captured during this test run. Password length validation was conclusively verified in Figure 5.

---

### Step 6: Successful Authentication & Clinical Dashboard Navigation

Upon entering valid administrative credentials, the application authenticated with Supabase Auth, updated the app state, and navigated to the primary Clinical Management Dashboard. Appium Inspector verified the complete widget hierarchy:

- **Header App Bar:** Admin user avatar ('A'), clinic branding ('MKES...'), Search, and Notifications bell.
- **Activity Metrics:** Weekly patient activity and revenue bar chart (Monday through Sunday).
- **Staff Attendance Widget:** Real-time clinical staff counts — **42 Present**, **3 On Leave** (OPD: 12/12 Optimal, Dental: 4/6 Short, Pharmacy: 5/5 Optimal).
- **Critical Inventory Widget:** Real-time medical supply status — *"All Stock Levels Healthy — No critical low-stock or expiring items."*
- **Bottom Navigation Bar:** Tab items for Dashboard (active), Staff, Patients, Operations, and Admin.

![Figure 6 — Authenticated Clinical Dashboard: Live Attendance KPIs and Navigation](assets/appium_fig6_dashboard_verification.png)
*Figure 6 — Authenticated Clinical Dashboard: Live Attendance KPIs, Stock Status, and Navigation Elements*

> **[Verification]** Confirms successful authentication transition, session persistence, and rendering of all clinical dashboard widgets in the Appium Inspector DOM tree.

---

### Step 7: Real Application Clinical Workflow — Patient Records Management

To verify end-to-end operational functionality, the test navigated to the Patients Management screen via the bottom navigation bar. The screen loaded live clinical records directly from the Supabase PostgreSQL database:

- **Patient Records Populated:** Live database records rendered — `P-4096` ("ag"), `E-0001` ("Eye Test Patient", Age 26), `E-0005` ("goat", Age 31), `E-0002` ("tatva"), `E-0003` ("Test").
- **Interactive Controls:** Department filter chips ("Eye", "Dental"), "Attendance" quick action, and "New Patient" creation button.
- **Search Interface:** Live filter bar ("Search by name, ID, or mobile...").

> **[Technical Distinction]** Unlike static or mock tests, rendering dynamic patient identifiers and medical history confirms live, unbroken communication between the Flutter mobile client and the cloud database backend over HTTPS REST.

![Figure 7 — Real Application Workflow: Patient Records Management and Database Data](assets/appium_fig7_patient_records_workflow.png)
*Figure 7 — Real Application Workflow: Patient Records Management, Department Filtering, and Database Data Inspection*

> **[Verification]** Validates end-to-end database connectivity: retrieving real patient entities from Supabase, rendering them in Flutter ListView, and inspecting element accessibility via Appium.

---

### Step 8: Automated Python Test Script Execution (`test_mkes_app.py`)

In addition to interactive Appium Inspector verification, automated test execution was verified via Python using the `Appium-Python-Client` (`D:\mkes-lovable\mobile_tests\test_mkes_app.py`):

```python
from appium import webdriver
from appium.options.android import UiAutomator2Options

options = UiAutomator2Options()
options.platform_name = "Android"
options.automation_name = "UiAutomator2"
options.device_name = "A142"
options.udid = "000703458000429"
options.app_package = "com.example.mkes_care"
options.app_activity = "com.example.mkes_care.MainActivity"
options.no_reset = True
options.set_capability("appium:ignoreHiddenApiPolicyError", True)
options.set_capability("appium:uiautomator2ServerInstallTimeout", 60000)

driver = None
try:
    driver = webdriver.Remote("http://127.0.0.1:4723", options=options)
    print("PASS: Appium session created.")
    assert driver.current_package == "com.example.mkes_care"
    print("PASS: MKES CARE+ app is running.")
    print("\nVisible screen text dump:\n", driver.page_source[:5000])
finally:
    if driver:
        driver.quit()
```

> **[Automation Distinction]** Connecting to Appium establishes WebDriver communication, while automated script execution asserts application state, validates element visibility, and performs headless regression testing.

---

## 4. Test Cases and Results

The following test suite was executed against the physical Android device running MKES CARE+:

| TC ID | Test Scenario | Expected Result | Actual Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **TC-01** | ADB Device Connection | Device detected in authorized `device` mode | `000703458000429` recognized by ADB daemon | **PASS** |
| **TC-02** | Appium Server Startup | REST HTTP listener starts on port 4723 | v3.8.0 listening on `0.0.0.0:4723`; UiAutomator2 loaded | **PASS** |
| **TC-03** | Inspector Session Launch | Screen mirrored; root FrameLayout rendered | Live screen displayed; `com.example.mkes_care` active | **PASS** |
| **TC-04** | UI Element Inspection | Resolve locators, bounds, and accessibility attributes | Derived UiSelector, XPath, and bounds (1009×277 px) | **PASS** |
| **TC-05** | Empty-Login Validation | Block submit; show mandatory field warnings | Not captured as separate screenshot in run | **MISSING\*** |
| **TC-06** | Password Length Check | Display 'Password must be at least 6 characters' | Red inline error rendered; submission blocked | **PASS** |
| **TC-07** | Admin Login & Dashboard | Authenticate and display clinical metrics | Loaded KPIs: 42 present, 3 on leave, healthy stock | **PASS** |
| **TC-08** | Patient Workflow (DB) | Retrieve and render live patient entities from DB | Rendered P-4096, E-0001, E-0005, E-0002, E-0003 | **PASS** |

*\*Note: TC-05 empty-form submission was not separately captured; password-length validation (TC-06) verified client-side validation guardrails.*

---

## 5. Screenshots and Evidence Summary

All visual evidence was captured live during test execution and embedded directly in Section 3:

- **Figure 1 (TC-01):** ADB device list showing physical device `000703458000429 device` connected (`appium_fig2_adb_device_connected.png`).
- **Figure 2 (TC-02):** Appium Server v3.8.0 terminal startup, UiAutomator2 driver load, and port 4723 listener (`appium_fig1_server_running.png`).
- **Figure 3 (TC-03):** Appium Inspector connected to `com.example.mkes_care` showing Role Selection UI tree (`appium_fig3_inspector_session_launch.png`).
- **Figure 4 (TC-04):** Element inspection of 'Admin Portal' button with bounding box (1009×277 px) and XPath (`appium_fig4_ui_hierarchy_inspection.png`).
- **Figure 5 (TC-06):** Input validation failure displaying 'Password must be at least 6 characters' in red (`appium_fig5_login_validation_error.png`).
- **Figure 6 (TC-07):** Authenticated Clinical Dashboard with Attendance (42 present) and Stock health KPIs (`appium_fig6_dashboard_verification.png`).
- **Figure 7 (TC-08):** Patient Records Management screen rendering live patient entities from Supabase cloud database (`appium_fig7_patient_records_workflow.png`).
- **Missing Evidence (TC-05):** Dedicated empty-login submission screenshot was omitted from the session captures.

---

## 6. Result and Conclusion

**Result:**  
Mobile UI testing and automated element inspection for the MKES CARE+ Flutter application were successfully demonstrated on a physical Android device (model A142, Android 16) using Appium Server v3.8.0, UiAutomator2, and Appium Inspector. Seven key operational milestones were conclusively proven: (1) ADB device connectivity, (2) Appium Server HTTP lifecycle, (3) W3C capability negotiation, (4) Flutter Semantics DOM element inspection, (5) client-side password length validation, (6) post-authentication dashboard rendering, and (7) live Supabase database record retrieval in the Patient module.

**Conclusion:**  
1. **Physical Device Reliability:** USB-tethered ADB communication provides higher fidelity testing than emulators, accurately reflecting hardware performance and touch response.
2. **Flutter Accessibility Integration:** Because Flutter compiles to canvas draw calls, comprehensive Appium automation relies strictly on Semantics nodes and content-descriptions.
3. **Verification vs Automation:** Interactive inspection in Appium Inspector allows fast locator discovery, which directly informs headless automated regression scripts in CI/CD pipelines.
4. **Transparent Quality Assurance:** Documenting verified tests alongside missing evidence guarantees academic integrity and practical rigor.

---

## 7. Essential Appium & ADB Commands Reference

| Purpose / Operation | Command Syntax |
| :--- | :--- |
| **List Connected Devices** | `adb devices` |
| **Install App to Device** | `adb install -r app-debug.apk` |
| **Start Appium Server** | `appium --address 127.0.0.1 --port 4723` |
| **Check Installed Drivers** | `appium driver list --installed` |
| **Install UiAutomator2 Driver** | `appium driver install uiautomator2` |
| **Capture Device Syslog** | `adb logcat *:E` |

---

## 8. Practical Viva Questions & Answers

**Q1: What is the role of UiAutomator2 in the Appium Android automation architecture?**  
*Answer:* UiAutomator2 is the underlying Android test automation framework provided by Google. Appium Server acts as a W3C WebDriver proxy that translates high-level client commands into UiAutomator2 REST requests, which are executed directly on the device by the Appium UiAutomator2 server instrumentation APK.

**Q2: How does testing a Flutter mobile application with Appium differ from testing native Android apps?**  
*Answer:* Native Android apps use standard Android View hierarchies (`TextView`, `Button`) easily indexed by `resource-id`. Flutter paints its UI directly onto a Skia/Impeller canvas, so standard Android view hierarchies do not exist. Appium relies on Flutter's Semantics tree, requiring developers to supply `content-description` or Semantics labels to expose element locators.

**Q3: What is the purpose of Appium Inspector, and how does it assist test development?**  
*Answer:* Appium Inspector is a graphical desktop utility that mirrors the mobile device screen, displays the complete XML DOM hierarchy, highlights element bounding boxes, and generates tested locators (such as XPath and UiSelector expressions), dramatically speeding up automated test script authoring.

**Q4: What is the difference between connecting to Appium and successfully testing an application?**  
*Answer:* Connecting to Appium simply verifies the WebDriver HTTP handshake and device session initialization. Testing requires interacting with application elements, triggering business logic, asserting UI state changes, validating form error handlers, and confirming data persistence.

**Q5: Why was port 4723 used for Appium while the web container in Task 4 ran on port 8081?**  
*Answer:* Port 4723 is the default standard port for Appium W3C WebDriver listeners. Port 8081 was allocated for the Nginx Docker container in Task 4 to isolate web hosting from local development tools (port 8080) and test daemons (port 4723), preventing port collision in multi-tiered DevOps environments.
