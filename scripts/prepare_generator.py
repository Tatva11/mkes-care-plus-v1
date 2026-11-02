import os
import re

print("Starting generation of MKES_CARE_FINAL_RESET_AND_SEED.sql...")

# Read the template from generate_clean_seed_sql.py
with open("scripts/generate_clean_seed_sql.py", "r", encoding="utf-8") as f:
    code = f.read()

# Fix the alias bug: replace 'IF p.id IS NOT NULL THEN' with 'IF v_rec.patient_id IS NOT NULL THEN'
code = code.replace("IF p.id IS NOT NULL THEN", "IF v_rec.patient_id IS NOT NULL THEN")

# Ensure header specifies MKES_CARE_FINAL_RESET_AND_SEED.sql
code = code.replace("scripts/clean_and_seed_demo_data.sql", "MKES_CARE_FINAL_RESET_AND_SEED.sql")

with open("scripts/generate_final_reset_and_seed.py", "w", encoding="utf-8") as f:
    f.write(code)

print("generate_final_reset_and_seed.py written.")

