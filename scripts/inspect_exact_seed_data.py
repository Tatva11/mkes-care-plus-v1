with open('MKES_CARE_FINAL_RESET_AND_SEED.sql', 'r', encoding='utf-8') as f:
    text = f.read()

import re
print("Invoices found:", re.findall(r"INV-[^\'\"]+", text)[:10])
print("Vendors found:", re.findall(r"INSERT INTO public\.vendors[\s\S]+?;", text)[:1])
print("Purchase orders found:", re.findall(r"INSERT INTO public\.purchase_orders[\s\S]+?;", text)[:1])
print("Dental lab found:", re.findall(r"INSERT INTO public\.dental_lab[\s\S]+?;", text)[:1])
print("Inventory found:", re.findall(r"INSERT INTO public\.inventory[\s\S]+?;", text)[:1])

