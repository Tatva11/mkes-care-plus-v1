import sys, os
sys.path.insert(0, 'scripts')
import map_all_fks

deletion_order = [
    # 1. Clinical Examinations & Dental Treatments (Children of appointments, eye_surgeries, dental_lab, patients)
    "clinical_inventory_usage",          # references inventory(inventory_id) RESTRICT, patients, inventory_transactions
    "eye_examinations",                  # references patients, appointments, eye_surgeries
    "dental_treatments",                 # references patients, appointments, dental_lab

    # 2. Eye Surgery dependents & cases (Children of inventory and patients)
    "eye_surgery_insurance_payments",    # references eye_surgery_insurances, eye_surgeries
    "eye_surgery_insurances",            # references eye_surgeries, patients
    "eye_surgery_inventory_consumptions",# references eye_surgeries
    "eye_surgery_notification_events",   # references eye_surgeries
    "eye_surgery_items",                 # references eye_surgeries, inventory(inventory_item_id) RESTRICT
    "eye_surgery_item_templates",        # references inventory(inventory_item_id) RESTRICT
    "eye_surgeries",                     # references patients, appointments

    # 3. Lab tracking & Appointment dependents
    "dental_lab",                        # references patients RESTRICT, appointments
    "whatsapp_message_logs",             # references whatsapp_messages_outbox, appointments, patients
    "whatsapp_messages_outbox",          # references appointments, patients
    "whatsapp_appointment_requests",     # references appointments, patients
    "patient_attendance",                # references patients
    "appointments",                      # references patients

    # 4. Inventory dependents & Purchase orders
    "inventory_batches",                 # references inventory, purchase_orders, purchase_order_items, vendors
    "purchase_order_items",              # references purchase_orders, inventory
    "purchase_orders",                   # references vendors
    "stock_requests",                    # references inventory RESTRICT, departments
    "department_inventory",              # references inventory, departments
    "inventory_transactions",            # references inventory, patients
    "inventory",                         # references vendors (all children referencing inventory deleted!)
    "vendors",                           # (all children referencing vendors deleted!)

    # 5. Billing & Payments
    "billing_payments",                  # references billing RESTRICT
    "billing_items",                     # references billing
    "billing",                           # references patients RESTRICT

    # 6. Tasks
    "task_history",                      # references tasks
    "tasks",

    # 7. Legacy tables referencing patients
    "optical_orders",
    "sales",

    # 8. Patients
    "patients"                           # all children referencing patients deleted!
]

print("=== CHECKING REVISED DELETION ORDER AGAINST ALL FKs ===")
table_indices = {tbl: i for i, tbl in enumerate(deletion_order)}

violations = []
for key, fk in map_all_fks.unique_fks.items():
    child = fk['source_table']
    parent = fk['ref_table']
    if child in table_indices and parent in table_indices:
        c_idx = table_indices[child]
        p_idx = table_indices[parent]
        if c_idx >= p_idx:
            violations.append(f"VIOLATION: Child {child} (index {c_idx}) is deleted AFTER or SAME as parent {parent} (index {p_idx}) via {fk['constraint']}")
        else:
            print(f"OK: Child {child} (index {c_idx}) -> Parent {parent} (index {p_idx}) [ON DELETE {fk['on_delete']}]")

if violations:
    print(f"\n--- FOUND {len(violations)} VIOLATIONS ---")
    for v in violations:
        print(v)
else:
    print("\nPERFECT: Zero dependency violations in the deletion sequence!")
