file_path = "lib/features/staff_portal/screens/staff_schedule_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Replace Reschedule with Edit / Reschedule
target1 = "label: const Text('Reschedule'),"
replacement1 = "label: const Text('Edit / Reschedule'),"

target2 = "label: const Text('Reschedule Missed'),"
replacement2 = "label: const Text('Edit / Reschedule Missed'),"

if target1 in content:
    content = content.replace(target1, replacement1)
    print("Replaced target1 successfully.")
else:
    print("target1 not found!")

if target2 in content:
    content = content.replace(target2, replacement2)
    print("Replaced target2 successfully.")
else:
    print("target2 not found!")

with open(file_path, "w", encoding="utf-8", newline="") as f:
    f.write(content)

print("Updated staff_schedule_screen.dart successfully.")

