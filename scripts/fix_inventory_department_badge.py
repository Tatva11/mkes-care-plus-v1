with open('lib/features/admin/widgets/inventory_alerts_card.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace(
    "departmentBadge: item.department.isNotEmpty ? item.department.toUpperCase() : null,",
    "departmentBadge: (item.department != null && item.department!.isNotEmpty) ? item.department!.toUpperCase() : null,"
)

with open('lib/features/admin/widgets/inventory_alerts_card.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('Fixed departmentBadge null check in inventory_alerts_card.dart!')

