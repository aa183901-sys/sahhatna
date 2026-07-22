/**
 * صحتنا - Password recovery
 * Handles Supabase PASSWORD_RECOVERY links without exposing credentials.
 */

let passwordRecoveryClient = null;

function setRecoveryStatus(message, type = 'info') {
  const status = document.getElementById('recoveryStatus');
  status.textContent = message;
  status.className = 'rounded-xl p-4 text-sm text-center';
  status.classList.add(type === 'error' ? 'bg-red-50' : type === 'success' ? 'bg-green-50' : 'bg-info-light');
  status.classList.add(type === 'error' ? 'text-red-700' : type === 'success' ? 'text-green-700' : 'text-gray-700');
}

function showRecoveryForm() {
  document.getElementById('resetPasswordForm').classList.remove('hidden');
  setRecoveryStatus('الرابط صالح. اكتب كلمة المرور الجديدة.', 'success');
}

async function initializePasswordRecovery() {
  try {
    passwordRecoveryClient = await initSupabase();

    const hash = new URLSearchParams(window.location.hash.slice(1));
    const query = new URLSearchParams(window.location.search);
    const errorCode = hash.get('error_code') || query.get('error_code');
    const errorDescription = hash.get('error_description') || query.get('error_description');

    if (errorCode) {
      setRecoveryStatus(
        errorCode === 'otp_expired'
          ? 'انتهت صلاحية الرابط. ارجع إلى لوحة الإدارة واطلب رابطاً جديداً.'
          : decodeURIComponent((errorDescription || 'رابط الاستعادة غير صالح').replace(/\+/g, ' ')),
        'error'
      );
      return;
    }

    const { data, error } = await passwordRecoveryClient.auth.getSession();
    if (error) throw error;

    if (data.session) {
      window.history.replaceState(null, '', window.location.pathname);
      showRecoveryForm();
      return;
    }

    const { data: listener } = passwordRecoveryClient.auth.onAuthStateChange((event, session) => {
      if (event === 'PASSWORD_RECOVERY' && session) {
        window.history.replaceState(null, '', window.location.pathname);
        showRecoveryForm();
      }
    });

    window.setTimeout(() => {
      if (document.getElementById('resetPasswordForm').classList.contains('hidden')) {
        setRecoveryStatus('الرابط غير صالح أو منتهي. اطلب رابط استعادة جديداً.', 'error');
        listener.subscription.unsubscribe();
      }
    }, 4000);
  } catch (error) {
    console.error('Password recovery initialization failed:', error);
    setRecoveryStatus('تعذر التحقق من الرابط. تأكد من اتصال الإنترنت وحاول مجدداً.', 'error');
  }
}

async function handlePasswordUpdate(event) {
  event.preventDefault();
  const password = document.getElementById('newPassword').value;
  const confirmation = document.getElementById('confirmPassword').value;
  const button = document.getElementById('updatePasswordButton');

  if (password.length < 12) {
    setRecoveryStatus('كلمة المرور يجب أن تكون 12 حرفاً على الأقل.', 'error');
    return;
  }
  if (password !== confirmation) {
    setRecoveryStatus('كلمتا المرور غير متطابقتين.', 'error');
    return;
  }

  button.disabled = true;
  button.textContent = 'جارٍ الحفظ...';

  try {
    const { error } = await passwordRecoveryClient.auth.updateUser({ password });
    if (error) throw error;
    await passwordRecoveryClient.auth.signOut();
    document.getElementById('resetPasswordForm').classList.add('hidden');
    setRecoveryStatus('تم تغيير كلمة المرور بنجاح. يمكنك تسجيل الدخول الآن.', 'success');
  } catch (error) {
    console.error('Password update failed:', error);
    setRecoveryStatus('لم يتم تغيير كلمة المرور. اطلب رابطاً جديداً وحاول مرة أخرى.', 'error');
    button.disabled = false;
    button.textContent = 'حفظ كلمة المرور';
  }
}

document.addEventListener('DOMContentLoaded', initializePasswordRecovery);
