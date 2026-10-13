
from appium import webdriver
from appium.options.android import UiAutomator2Options
from appium.webdriver.common.appiumby import AppiumBy
import time

options = UiAutomator2Options()
options.platform_name = "Android"
options.automation_name = "UiAutomator2"
options.device_name = "CPH2359"
options.udid = "IVRSDMF6WOMFLNOV"
options.app_package = "com.example.mkes_care"
options.app_activity = "com.example.mkes_care.MainActivity"
options.no_reset = True
options.set_capability("appium:ignoreHiddenApiPolicyError", True)
options.set_capability("appium:uiautomator2ServerInstallTimeout", 60000)

driver = None

try:
    driver = webdriver.Remote(
        "http://127.0.0.1:4723",
        options=options
    )

    print("PASS: Appium session created.")
    print("Current app:", driver.current_package)

    assert driver.current_package == "com.example.mkes_care"
    print("PASS: MKES CARE+ app is running.")

    print("\nVisible screen text:")
    print(driver.page_source[:5000])

except Exception as error:
    print("FAIL:", error)
    raise

finally:
    if driver:
        driver.quit()
