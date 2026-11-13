#!/bin/bash
set -e

git clone --depth 1 -b stable https://github.com/flutter/flutter.git /tmp/flutter
export PATH="/tmp/flutter/bin:$PATH"

flutter config --enable-web

printf 'SUPABASE_URL=%s\nSUPABASE_ANON_KEY=%s\n' "$SUPABASE_URL" "$SUPABASE_ANON_KEY" > api.env

flutter pub get
flutter build web --release
