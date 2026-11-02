with open('scripts/generate_final_reset_and_seed.py', 'r', encoding='utf-8') as f:
    text = f.read()

target = "  -- Doctors\n  SELECT doctor_id INTO v_eye_doc_id FROM public.department_doctors WHERE is_active = true LIMIT 1;\n  IF v_eye_doc_id IS NULL THEN v_eye_doc_id := v_admin_id; END IF;\n  \n  v_dental_doc_id := v_eye_doc_id;"

replacement = """  -- Doctors (appointments.doctor_id foreign key references public.profiles(id))
  SELECT id INTO v_eye_doc_id FROM public.profiles WHERE role = 'doctor' AND is_active = true LIMIT 1;
  IF v_eye_doc_id IS NULL THEN
    SELECT id INTO v_eye_doc_id FROM public.profiles WHERE role IN ('admin', 'staff') AND is_active = true LIMIT 1;
  END IF;
  IF v_eye_doc_id IS NULL THEN v_eye_doc_id := v_admin_id; END IF;
  v_dental_doc_id := v_eye_doc_id;"""

if target in text:
    text = text.replace(target, replacement)
    with open('scripts/generate_final_reset_and_seed.py', 'w', encoding='utf-8') as f:
        f.write(text)
    print("Replaced doctor query successfully!")
else:
    # Try CRLF
    target_crlf = target.replace('\n', '\r\n')
    if target_crlf in text:
        text = text.replace(target_crlf, replacement.replace('\n', '\r\n'))
        with open('scripts/generate_final_reset_and_seed.py', 'w', encoding='utf-8') as f:
            f.write(text)
        print("Replaced doctor query (CRLF) successfully!")
    else:
        print("Target not found!")

