with open('lib/features/admin/widgets/revenue_growth_card.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Replace the broken multiline string
old_target = """    final String tooltipMessage = hasRevenue
        ? '${slot.fullLabel}
Revenue: ${currency.format(slot.amount)}
${slot.transactionCount} transaction${slot.transactionCount == 1 ? '' : 's'}'
        : '${slot.fullLabel}
Revenue: ₹0 (No collections)';"""

new_replacement = """    final String tooltipMessage = hasRevenue
        ? '${slot.fullLabel}\\nRevenue: ${currency.format(slot.amount)}\\n${slot.transactionCount} transaction${slot.transactionCount == 1 ? '' : 's'}'
        : '${slot.fullLabel}\\nRevenue: ₹0 (No collections)';"""

# Try both CRLF and LF
if old_target in text:
    text = text.replace(old_target, new_replacement)
elif old_target.replace('\n', '\r\n') in text:
    text = text.replace(old_target.replace('\n', '\r\n'), new_replacement.replace('\n', '\r\n'))
else:
    print('Pattern not found, will regex replace')
    import re
    text = re.sub(
        r"final String tooltipMessage = hasRevenue\s*\?\s*'\$\{slot\.fullLabel\}[\r\n]+Revenue:[^\r\n]+[\r\n]+[^\r\n]+'\s*:\s*'\$\{slot\.fullLabel\}[\r\n]+Revenue:[^\r\n]+';",
        new_replacement,
        text
    )

with open('lib/features/admin/widgets/revenue_growth_card.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('Fixed tooltipMessage in revenue_growth_card.dart!')

