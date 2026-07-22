/**
 * صحتنا - Clinic Activation Logic
 * Handles clinic account activation via activation code.
 * Flow: Admin approves clinic → generates code → clinic owner activates here.
 */

function showToast(message, type = 'success') {
  const container = document.getElementById('toastContainer');
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transition = 'opacity 0.3s';
    setTimeout(() => toast.remove(), 300);
  }, 4000);
}

function prefillActivationDetails() {
  const params = new URLSearchParams(window.location.hash.slice(1));
  const clinicName = (params.get('clinic') || '').trim();
  const activationCode = (params.get('code') || '').trim().toUpperCase();
  const clinicNameInput = document.getElementById('activateClinicName');
  const codeInput = document.getElementById('activateCode');

  if (clinicName && clinicNameInput) {
    clinicNameInput.value = clinicName;
    clinicNameInput.readOnly = true;
    clinicNameInput.setAttribute('aria-readonly', 'true');
  }

  if (/^[A-Z0-9]{6}$/.test(activationCode) && codeInput) {
    codeInput.value = activationCode;
    codeInput.readOnly = true;
    codeInput.setAttribute('aria-readonly', 'true');
  }
}

async function handleActivate(event) {
  event.preventDefault();

  const clinicName = document.getElementById('activateClinicName').value.trim();
  const activationCode = document.getElementById('activateCode').value.trim().toUpperCase();
  const username = document.getElementById('activateUsername').value.trim().toLowerCase();
  const email = document.getElementById('activateEmail').value.trim().toLowerCase();
  const password = document.getElementById('activatePassword').value;
  const passwordConfirm = document.getElementById('activatePasswordConfirm').value;

  // Client-side validation
  if (activationCode.length !== 6) {
    showToast('رمز التفعيل يجب أن يكون 6 محارف', 'error');
    return;
  }

  if (password !== passwordConfirm) {
    showToast('كلمتا المرور غير متطابقتين', 'error');
    return;
  }

  if (password.length < 8) {
    showToast('كلمة المرور يجب أن تكون 8 محارف على الأقل', 'error');
    return;
  }

  if (username.length < 3) {
    showToast('اسم المستخدم يجب أن يكون 3 محارف على الأقل', 'error');
    return;
  }

  // Username must be alphanumeric (no spaces, no special chars)
  if (!/^[a-z0-9_]+$/.test(username)) {
    showToast('اسم المستخدم يجب أن يحتوي أحرف لاتينية أو أرقام فقط', 'error');
    return;
  }

  const btn = document.getElementById('activateBtn');
  btn.disabled = true;
  btn.textContent = 'جاري التفعيل...';

  try {
    const result = await SahatnaDB.activateClinic(clinicName, activationCode, username, email, password);
    showToast(`تم تفعيل حسابك بنجاح! مرحباً بك في ${result.clinic.name}`, 'success');
    // Redirect to clinic login page after short delay
    setTimeout(() => {
      window.location.href = 'clinic.html';
    }, 2000);
  } catch (error) {
    showToast(error.message || 'فشل التفعيل', 'error');
    btn.disabled = false;
    btn.textContent = 'تفعيل الحساب';
  }
}

// Auto-uppercase the activation code input
document.addEventListener('DOMContentLoaded', () => {
  prefillActivationDetails();
  const codeInput = document.getElementById('activateCode');
  if (codeInput) {
    codeInput.addEventListener('input', (e) => {
      e.target.value = e.target.value.toUpperCase();
    });
  }
});
