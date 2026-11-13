import os
import sys
import uuid
import getpass
import openpyxl

try:
    import psycopg2
    from psycopg2 import extras
except ImportError:
    print("Error: psycopg2 is required. Run 'pip install psycopg2-binary' first.")
    sys.exit(1)

EXCEL_PATH = r'D:\mkes-lovable\Copy of Pt database.xlsx'
NS = uuid.UUID('6ba7b810-9dad-11d1-80b4-00c04fd430c8')

def mask_connection_string(conn_str):
    import re
    return re.sub(r':([^@]+)@', ':****@', conn_str)

def load_excel_records():
    print(f"\n[1/6] Loading source Excel file: {EXCEL_PATH}...")
    wb = openpyxl.load_workbook(EXCEL_PATH, data_only=True)
    
    dental_sheet = wb['Dental']
    dental_records = []
    for row_idx, row in enumerate(dental_sheet.iter_rows(min_row=2, values_only=True), start=2):
        raw_id = row[0]
        name = row[1]
        age = row[2]
        sex = row[3]
        address = row[4]
        contact1 = row[5]
        contact2 = row[6] 
        email = row[7]
        referral = row[8]
        
        has_name = name is not None and str(name).strip() != ''
        has_details = any(v is not None and str(v).strip() != '' for v in [contact1, address, age, sex])
        
        if has_name or has_details:
            patient_num = str(raw_id).strip() if raw_id is not None else ''
            patient_name = str(name).strip() if name is not None else ''
            
            ref_parts = []
            if referral and str(referral).strip():
                ref_parts.append(f"Referral: {str(referral).strip()}")
            if email and str(email).strip():
                ref_parts.append(f"Email: {str(email).strip()}")
            if contact2 and str(contact2).strip():
                c2 = str(contact2).strip()
                if c2.endswith('.0'): c2 = c2[:-2]
                ref_parts.append(f"Contact 2: {c2}")
                
            ref_text = " | ".join(ref_parts) if ref_parts else None
            
            # Numeric age and calculated dob
            age_num = None
            dob_val = None
            if age is not None:
                try:
                    af = float(age)
                    if 0 < af <= 130:
                        age_num = int(af) if af.is_integer() else af
                        dob_val = f"{2026 - int(af):04d}-01-01"
                except Exception:
                    pass
                    
            c1_str = str(contact1).strip() if contact1 is not None else None
            if c1_str and c1_str.endswith('.0'): c1_str = c1_str[:-2]
            
            row_uuid = str(uuid.uuid5(NS, f"Dental:{row_idx}:{patient_num}:{patient_name}"))
            
            dental_records.append((
                row_uuid,
                patient_num,
                patient_name,
                dob_val,
                age_num,
                str(sex).strip() if sex is not None else None,
                str(address).strip() if address is not None else None,
                c1_str,
                'dental',
                ref_text
            ))

    eye_sheet = wb['EYE']
    eye_records = []
    for row_idx, row in enumerate(eye_sheet.iter_rows(min_row=2, values_only=True), start=2):
        raw_id = row[0]
        name = row[1]
        age = row[2]
        sex = row[3]
        address = row[4]
        contact = row[5]
        email = row[7]
        ref_by = row[8]
        ref_details = row[9]
        advise = row[11]
        
        has_name = name is not None and str(name).strip() != ''
        has_details = any(v is not None and str(v).strip() != '' for v in [contact, address, age, sex])
        
        if has_name or has_details:
            patient_num = str(raw_id).strip() if raw_id is not None else ''
            if patient_num.endswith('.0'):
                patient_num = patient_num[:-2]
                
            patient_name = str(name).strip() if name is not None else ''
            
            ref_parts = []
            if ref_by and str(ref_by).strip():
                ref_parts.append(f"Referred by: {str(ref_by).strip()}")
            if ref_details and str(ref_details).strip():
                ref_parts.append(f"Referral details: {str(ref_details).strip()}")
            if email and str(email).strip():
                ref_parts.append(f"Email: {str(email).strip()}")
            if advise and str(advise).strip():
                ref_parts.append(f"Advise: {str(advise).strip()}")
                
            ref_text = " | ".join(ref_parts) if ref_parts else None
            
            age_num = None
            dob_val = None
            if age is not None:
                try:
                    af = float(age)
                    if 0 < af <= 130:
                        age_num = int(af) if af.is_integer() else af
                        dob_val = f"{2026 - int(af):04d}-01-01"
                except Exception:
                    pass
                    
            c_str = str(contact).strip() if contact is not None else None
            if c_str and c_str.endswith('.0'): c_str = c_str[:-2]
            
            row_uuid = str(uuid.uuid5(NS, f"EYE:{row_idx}:{patient_num}:{patient_name}"))
            
            eye_records.append((
                row_uuid,
                patient_num,
                patient_name,
                dob_val,
                age_num,
                str(sex).strip() if sex is not None else None,
                str(address).strip() if address is not None else None,
                c_str,
                'eye',
                ref_text
            ))

    total = len(dental_records) + len(eye_records)
    print(f"  Dental Records Extracted: {len(dental_records)}")
    print(f"  Eye Records Extracted   : {len(eye_records)}")
    print(f"  Total Patient Records   : {total}")
    return dental_records, eye_records

def run_import(db_url):
    print(f"\n[2/6] Connecting to PostgreSQL at: {mask_connection_string(db_url)}...")
    conn = psycopg2.connect(db_url)
    conn.autocommit = False
    cur = conn.cursor()
    
    try:
        # Step 1: Pre-import backup
        print("\n[3/6] Backing up existing patient records...")
        cur.execute("SELECT count(*) FROM public.patients;")
        existing_count = cur.fetchone()[0]
        print(f"  Current active patients in database: {existing_count}")
        
        cur.execute("DROP TABLE IF EXISTS public.patients_pre_excel_backup;")
        cur.execute("CREATE TABLE public.patients_pre_excel_backup AS SELECT * FROM public.patients;")
        
        cur.execute("SELECT count(*) FROM public.patients_pre_excel_backup;")
        backup_count = cur.fetchone()[0]
        print(f"  Backup created: public.patients_pre_excel_backup ({backup_count} rows)")
        
        if backup_count != existing_count:
            raise Exception(f"Backup verification failed! Expected {existing_count} rows, backed up {backup_count}")
        print("  Backup VERIFIED successfully.")

        # Step 2: Ensure schema compatibility
        print("\n[4/6] Ensuring supporting columns & constraints...")
        cur.execute("ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS age numeric;")
        cur.execute("ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS gender text;")
        cur.execute("ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS reference text;")
        
        # Drop unique constraint to allow exact raw duplicate IDs from Excel
        cur.execute("ALTER TABLE public.patients DROP CONSTRAINT IF EXISTS patients_patient_number_key;")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_patients_patient_number ON public.patients USING btree (patient_number);")

        # Step 3: Clear old patient records
        print("\n[5/6] Replacing patient records with exact Excel data...")
        # Bypass triggers for bulk load speed
        cur.execute("SET LOCAL session_replication_role = 'replica';")
        cur.execute("ALTER TABLE IF EXISTS public.patients DISABLE TRIGGER USER;")
        
        cur.execute("DELETE FROM public.patients;")
        print("  Cleared old patient records.")

        dental_records, eye_records = load_excel_records()
        all_records = dental_records + eye_records
        total_expected = len(all_records)

        # Step 4: High-speed batched insert using execute_values
        insert_query = """
        INSERT INTO public.patients (
            id, patient_number, name, dob, age, gender, address, mobile, department, reference
        ) VALUES %s
        """
        
        batch_size = 2000
        total_inserted = 0
        for i in range(0, len(all_records), batch_size):
            batch = all_records[i:i + batch_size]
            extras.execute_values(cur, insert_query, batch, page_size=len(batch))
            total_inserted += len(batch)
            print(f"  Inserted {total_inserted}/{total_expected} records ({(total_inserted*100)//total_expected}%)...")

        # Re-enable triggers and origin mode
        cur.execute("ALTER TABLE IF EXISTS public.patients ENABLE TRIGGER USER;")
        cur.execute("SET LOCAL session_replication_role = 'origin';")

        # Step 5: Post-import verification
        print("\n[6/6] Verifying database records against Excel source...")
        cur.execute("SELECT count(*) FROM public.patients;")
        db_total = cur.fetchone()[0]
        
        cur.execute("SELECT count(*) FROM public.patients WHERE department = 'dental';")
        db_dental = cur.fetchone()[0]
        
        cur.execute("SELECT count(*) FROM public.patients WHERE department = 'eye';")
        db_eye = cur.fetchone()[0]
        
        cur.execute("""
        SELECT count(*) FROM (
            SELECT patient_number, count(*) FROM public.patients GROUP BY patient_number HAVING count(*) > 1
        ) d;
        """)
        db_duplicates = cur.fetchone()[0]

        print("==================================================")
        print("POST-IMPORT DATABASE VERIFICATION AUDIT")
        print("==================================================")
        print(f"Total Patients in Database: {db_total} (Expected: {total_expected})")
        print(f"  - Dental Department     : {db_dental} (Expected: {len(dental_records)})")
        print(f"  - Eye Department        : {db_eye} (Expected: {len(eye_records)})")
        print(f"Duplicate Patient IDs Retained: {db_duplicates}")
        print("==================================================")

        if db_total != total_expected:
            raise Exception(f"Post-import row count mismatch! Expected {total_expected}, found {db_total}")

        # Commit transaction
        conn.commit()
        print("\nSUCCESS: Transaction COMMITTED. All patient records successfully replaced!")
        
    except Exception as e:
        conn.rollback()
        print(f"\nERROR OCCURRED: {e}")
        print("Transaction ROLLED BACK. No changes were committed.")
        sys.exit(1)
    finally:
        cur.close()
        conn.close()

if __name__ == '__main__':
    if '--help' in sys.argv or '-h' in sys.argv:
        print("=" * 70)
        print("MKES CARE+ Direct PostgreSQL Patient Database Importer")
        print("=" * 70)
        print("Usage:")
        print("  1. Interactive secure prompt (password hidden):")
        print("     python scripts/import_patients_pg.py\n")
        print("  2. Via environment variable:")
        print("     $env:DATABASE_URL=\"postgresql://postgres:[PASSWORD]@db.[REF].supabase.co:5432/postgres\"")
        print("     python scripts/import_patients_pg.py\n")
        print("  3. Direct argument:")
        print("     python scripts/import_patients_pg.py \"postgresql://postgres:[PASSWORD]@db.[REF].supabase.co:5432/postgres\"")
        print("=" * 70)
        sys.exit(0)

    # Check DATABASE_URL from env or args or prompt
    db_url = os.environ.get('DATABASE_URL')
    
    if not db_url and len(sys.argv) > 1:
        db_url = sys.argv[1]
        
    if not db_url:
        # Check scratch/db_config.txt if present
        cfg_path = r'C:\Users\Tatva jain\.gemini\antigravity\brain\fc41ee54-d2cb-4564-92fb-326487892ce6\scratch\db_config.txt'
        if os.path.exists(cfg_path):
            with open(cfg_path, 'r', encoding='utf-8') as f:
                db_url = f.read().strip()

    if not db_url:
        print("="*60)
        print("MKES CARE+ Direct PostgreSQL Patient Database Importer")
        print("="*60)
        print("Please provide the Supabase PostgreSQL connection string.")
        print("Example: postgresql://postgres.[ref]:[password]@aws-0-ap-south-1.pooler.supabase.com:6543/postgres")
        print("(You can find this in Supabase Dashboard -> Project Settings -> Database -> Connection String)")
        print("="*60)
        db_url = getpass.getpass("Enter PostgreSQL Connection String (hidden input): ")

    if not db_url:
        print("Error: No connection string provided.")
        sys.exit(1)

    run_import(db_url)
