import sys, os
sys.path.insert(0, 'scripts')
import map_all_fks

for target in ['inventory', 'eye_surgeries', 'patients', 'vendors', 'purchase_orders', 'billing', 'appointments', 'dental_lab']:
    print(f"\n=== TABLES REFERENCING [{target.upper()}] ===")
    for key, fk in map_all_fks.unique_fks.items():
        if fk['ref_table'] == target:
            print(f"  {fk['source_table']:35} ({','.join(fk['source_cols'])}) [ON DELETE {fk['on_delete']}] in {os.path.basename(fk['file'])}")
