#!/usr/bin/env bash
#
# بناء نسخة الويب بإعدادات Firebase صحيحة — أو الفشل بوضوح.
#
# ## المشكلة التي يحلّها هذا السكربت
#
# `flutter build web --release` **ينجح** حتى لو كانت مفاتيح Firebase للويب
# فارغة، لأن `String.fromEnvironment` بلا قيمة افتراضية يعطي نصاً فارغاً وقت
# الترجمة لا خطأً. الناتج حزمة تبدو سليمة، يرفعها `firebase deploy` (لأن
# firebase.json يشير إلى build/web)، فيرى كل زائر شاشة «إعدادات Firebase غير
# مضبوطة» بدل التطبيق.
#
# البناء الصامت الخاطئ هو العطل. هذا السكربت يقلبه إلى فشل صريح **قبل** إنتاج
# أي حزمة.
#
# ## الاستخدام
#
#     tool/build_web.sh                      # يقرأ web_config.json
#     tool/build_web.sh --config other.json  # ملف إعدادات آخر
#
# أو بتمرير المتغيّرات مباشرة (مفيد في CI):
#
#     FIREBASE_WEB_API_KEY=… FIREBASE_WEB_APP_ID=… tool/build_web.sh
#
# ## من أين تأتي القيم
#
# Firebase Console ← Project settings ← Your apps ← Web app ← SDK setup.
# مشروع `heldoc-68abf` لا يحتوي على تطبيق ويب مسجَّل بعد، فلا بد من إنشائه أولاً.
# القيم ليست أسراراً — تصل إلى المتصفح بالضرورة، وما يحمي البيانات هو
# firestore.rules. توثيق كامل في docs/RELEASE.md.

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG_FILE="web_config.json"
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

# المتغيّران الوحيدان اللذان لا قيمة افتراضية لهما في lib/firebase_options.dart.
# لو أُضيف متغيّر إلزامي ثالث هناك، يجب إضافته هنا — ويحرس ذلك اختبار
# test/web_config_test.dart الذي يقارن هذه القائمة بالملف مباشرة.
REQUIRED=(FIREBASE_WEB_API_KEY FIREBASE_WEB_APP_ID)

DEFINE_ARGS=()
MISSING=()

if [[ -f "$CONFIG_FILE" ]]; then
  echo "▸ إعدادات الويب من: $CONFIG_FILE"
  DEFINE_ARGS+=("--dart-define-from-file=$CONFIG_FILE")
  for key in "${REQUIRED[@]}"; do
    # قيمة غير فارغة للمفتاح داخل ملف JSON مسطّح.
    if ! grep -qE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" "$CONFIG_FILE"; then
      MISSING+=("$key")
    fi
  done
else
  for key in "${REQUIRED[@]}"; do
    value="${!key:-}"
    if [[ -z "$value" ]]; then
      MISSING+=("$key")
    else
      DEFINE_ARGS+=("--dart-define=$key=$value")
    fi
  done
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  cat >&2 <<EOF

╭──────────────────────────────────────────────────────────────╮
│  تعذّر بناء نسخة الويب: إعدادات Firebase ناقصة                │
╰──────────────────────────────────────────────────────────────╯

الناقص: ${MISSING[*]}

بدون هذه القيم يُنتج flutter حزمة تعمل ظاهرياً لكنها تعرض شاشة خطأ لكل
زائر. لذلك يتوقّف البناء هنا بدل إنتاجها.

الحل:

  1. سجّل تطبيق ويب في مشروع heldoc-68abf إن لم يكن مسجَّلاً:
     Firebase Console ← Project settings ← Your apps ← Add app ← Web

  2. انسخ القالب واملأه:

       cp web_config.example.json web_config.json
       \$EDITOR web_config.json

     (web_config.json مستثنى في .gitignore.)

  3. أعد التشغيل:

       tool/build_web.sh

التفاصيل في docs/RELEASE.md.
EOF
  exit 1
fi

echo "▸ flutter build web --release"
flutter build web --release "${DEFINE_ARGS[@]}" "${EXTRA_ARGS[@]}"

echo
echo "✓ تم البناء في build/web"
echo "  للنشر (بعد مراجعتك): firebase deploy --only hosting"
