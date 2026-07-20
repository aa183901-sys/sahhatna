 /**
 * صحتنا - Admin Panel Logic
 * Handles admin login, clinic approval, doctors, bookings, and analytics.
 * All SahatnaDB calls are async (Supabase or localStorage).
 */

let currentAdmin = null;

const escapeHTML = (value) => SahatnaDB.escapeHTML(value);
const safeImageURL = (value) => SahatnaDB.safeImageURL(value);
const escapeCSVCell = (value) => {
  let text = String(value == null ? '' : value);
  if (/^[=+\-@]/.test(text)) text = "'" + text;
  return `"${text.replace(/"/g, '""')}"`;
};

function showToast(message, type = 'success') {
  const container = document.getElementById('toastContainer');
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => { toast.style.opacity = '0'; toast.style.transition = 'opacity 0.3s'; setTimeout(() => toast.remove(), 300); }, 3000);
}

function formatPrice(price) { return new Intl.NumberFormat('ar-IQ').format(price) + ' د.ع'; }

function getClinicStatusBadge(status) {
  const badges = { approved: '<span class="badge badge-success">موافق عليها</span>', pending: '<span class="badge badge-warning">بانتظار الموافقة</span>', rejected: '<span class="badge badge-danger">مرفوضة</span>' };
  return badges[status] || badges.pending;
}

function getBookingStatusBadge(status) {
  const badges = { confirmed: '<span class="badge badge-info">مؤكد</span>', completed: '<span class="badge badge-success">مكتمل</span>', cancelled: '<span class="badge badge-danger">ملغي</span>', no_show: '<span class="badge badge-warning">لم يحضر</span>' };
  return badges[status] || badges.confirmed;
}

function getServiceLabel(service) {
  const labels = { clinic: 'زيارة عيادة', video: 'استشارة فيديو', home: 'زيارة منزلية' };
  return labels[service] || service;
}

async function handleAdminLogin(event) {
  event.preventDefault();
  const username = document.getElementById('adminUsername').value.trim();
  const password = document.getElementById('adminPassword').value.trim();
  try {
    const admin = await SahatnaDB.adminLogin(username, password);
    if (admin) {
      currentAdmin = admin;
      sessionStorage.setItem('sahatna_admin', JSON.stringify({ username: admin.username }));
      await showAdminDashboard();
      showToast('تم تسجيل الدخول بنجاح', 'success');
    } else {
      showToast('اسم المستخدم أو كلمة المرور غير صحيحة', 'error');
    }
  } catch (error) {
    console.error('Admin login failed:', error);
    showToast('تعذر الاتصال بخدمة تسجيل الدخول', 'error');
  }
}

async function adminLogout() {
  await SahatnaDB.signOut();
  sessionStorage.removeItem('sahatna_admin');
  currentAdmin = null;
  document.getElementById('adminDashboard').classList.add('hidden');
  document.getElementById('adminLoginScreen').classList.remove('hidden');
  showToast('تم تسجيل الخروج', 'info');
}

async function checkAdminSession() {
  if (SahatnaDB.isSupabaseEnabled()) {
    const admin = await SahatnaDB.getCurrentAdmin();
    if (admin) {
      currentAdmin = admin;
      sessionStorage.setItem('sahatna_admin', JSON.stringify({ username: admin.username }));
      await showAdminDashboard();
    } else {
      sessionStorage.removeItem('sahatna_admin');
    }
    return;
  }
  const saved = sessionStorage.getItem('sahatna_admin');
  if (saved) {
    try {
      const { username } = JSON.parse(saved);
      currentAdmin = { username, name: 'مدير صحتنا' };
      await showAdminDashboard();
    } catch (e) {
      console.error('Admin session restore error:', e);
      sessionStorage.removeItem('sahatna_admin');
    }
  }
}

async function showAdminDashboard() {
  document.getElementById('adminLoginScreen').classList.add('hidden');
  document.getElementById('adminDashboard').classList.remove('hidden');
  await renderAdminStats();
  await renderAdminClinics();
  await renderAdminDoctors();
  await renderAdminBookings();
  await renderAdminSpecialties();
  await renderAdminCities();
  await renderAdminAnalytics();
}

async function renderAdminStats() {
  const stats = await SahatnaDB.getStats();
  document.getElementById('adminStatPatients').textContent = stats.totalPatients;
  document.getElementById('adminStatApproved').textContent = stats.approvedClinics;
  document.getElementById('adminStatTotalClinics').textContent = stats.totalClinics;
  document.getElementById('adminStatPending').textContent = stats.pendingClinics + ' بانتظار الموافقة';
  document.getElementById('adminStatDoctors').textContent = stats.totalDoctors;
  document.getElementById('adminStatBookings').textContent = stats.totalBookings;
  document.getElementById('adminStatConfirmed').textContent = stats.confirmedBookings;
  document.getElementById('adminStatCompleted').textContent = stats.completedBookings;
  document.getElementById('adminStatCancelled').textContent = stats.cancelledBookings;
  document.getElementById('adminStatRevenue').textContent = formatPrice(stats.totalRevenue);
}

function switchAdminTab(tabName) {
  document.querySelectorAll('.tab-content').forEach((t) => t.classList.add('hidden'));
  document.querySelectorAll('.tab-btn').forEach((b) => b.classList.remove('active'));
  document.getElementById('tab-' + tabName).classList.remove('hidden');
  document.querySelector(`[data-tab="${tabName}"]`).classList.add('active');
  if (tabName === 'analytics') renderAdminAnalytics();
}

async function renderAdminClinics() {
  const db = await SahatnaDB.load();
  const statusFilter = document.getElementById('clinicStatusFilter').value;
  let clinics = db.clinics;
  if (statusFilter) clinics = clinics.filter((c) => c.status === statusFilter);
  const list = document.getElementById('adminClinicsList');
  if (clinics.length === 0) { list.innerHTML = `<div class="empty-state"><div class="empty-state-icon">🏥</div><p class="text-gray-400">لا توجد عيادات</p></div>`; return; }
  const cards = [];
  for (const clinic of clinics) {
    const city = db.cities.find((c) => c.id === clinic.cityId);
    const doctors = db.doctors.filter((d) => d.clinicId === clinic.id);
    const bookings = await SahatnaDB.getBookingsByClinic(clinic.id);
    const created = new Date(clinic.createdAt).toLocaleDateString('ar-IQ');
    cards.push(`
      <div class="border border-gray-200 rounded-2xl p-4 bg-white animate-fade-in">
        <div class="flex items-start justify-between gap-3 flex-wrap">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1">
              <h4 class="font-bold text-gray-800">${escapeHTML(clinic.name)}</h4>
              ${getClinicStatusBadge(clinic.status)}
            </div>
            <div class="text-sm text-gray-500 space-y-1">
              <p>📍 ${escapeHTML(clinic.area)}، ${escapeHTML(city ? city.name : '')}</p>
              <p>🏠 ${escapeHTML(clinic.address)}</p>
              <p>📞 ${escapeHTML(clinic.phone)}</p>
              <p>📅 تاريخ التسجيل: ${created}</p>
              <p>👨‍⚕️ ${doctors.length} طبيب • 📅 ${bookings.length} حجز</p>
            </div>
          </div>
          <div class="flex flex-col gap-2 flex-shrink-0">
            ${clinic.status === 'pending' ? `
              <button onclick="approveClinic('${clinic.id}')" class="btn-success text-xs">✓ موافقة</button>
              <button onclick="rejectClinic('${clinic.id}')" class="btn-danger text-xs">✕ رفض</button>
            ` : ''}
            ${clinic.status === 'approved' ? `<button onclick="rejectClinic('${clinic.id}')" class="btn-danger text-xs">إيقاف</button>` : ''}
            ${clinic.status === 'rejected' ? `<button onclick="approveClinic('${clinic.id}')" class="btn-success text-xs">إعادة تفعيل</button>` : ''}
          </div>
        </div>
      </div>
    `);
  }
  list.innerHTML = cards.join('');
}

async function approveClinic(clinicId) {
  const clinic = await SahatnaDB.approveClinic(clinicId);
  await renderAdminClinics();
  await renderAdminStats();
  const code = clinic.activationCode || clinic.activation_code;
  showToast(`تمت الموافقة على العيادة. كود التفعيل: ${code}`, 'success');
  alert(`تمت الموافقة على العيادة بنجاح!\n\nكود التفعيل: ${code}\n\nانسخ هذا الكود وأعطه للعيادة لتفعيل حسابها.`);
}

async function rejectClinic(clinicId) {
  if (confirm('هل أنت متأكد من رفض/إيقاف هذه العيادة؟')) {
    await SahatnaDB.rejectClinic(clinicId);
    await renderAdminClinics();
    await renderAdminStats();
    showToast('تم رفض/إيقاف العيادة', 'info');
  }
}

async function renderAdminDoctors() {
  const db = await SahatnaDB.load();
  const list = document.getElementById('adminDoctorsList');
  if (db.doctors.length === 0) { list.innerHTML = `<div class="col-span-full empty-state"><div class="empty-state-icon">👨‍⚕️</div><p class="text-gray-400">لا يوجد أطباء مسجلون</p></div>`; return; }
  const cards = [];
  for (const d of db.doctors) {
    const specialty = db.specialties.find((s) => s.id === d.specialtyId);
    const clinic = db.clinics.find((c) => c.id === d.clinicId);
    const city = clinic ? db.cities.find((c) => c.id === clinic.cityId) : null;
    const bookings = await SahatnaDB.getBookingsByDoctor(d.id);
    const revenue = bookings.filter((b) => b.status === 'completed').reduce((sum, b) => sum + b.price, 0);
    cards.push(`
      <div class="border border-gray-200 rounded-2xl p-4 bg-white">
        <div class="flex gap-3">
          <img src="${safeImageURL(d.photo)}" class="w-16 h-16 rounded-xl object-cover" />
          <div class="flex-1">
            <div class="flex items-center gap-2">
              <h4 class="font-bold text-gray-800">${escapeHTML(d.name)}</h4>
              ${d.verified ? '<span class="verified-badge">✓</span>' : ''}
              ${d.featured ? '<span class="badge badge-warning text-xs">مميز</span>' : ''}
            </div>
            <p class="text-sm text-primary">${escapeHTML(specialty ? specialty.name : '')}</p>
            <p class="text-xs text-gray-500 mt-1">📍 ${escapeHTML(clinic ? clinic.name : '')} - ${escapeHTML(city ? city.name : '')}</p>
          </div>
        </div>
        <div class="grid grid-cols-4 gap-2 mt-3 pt-3 border-t border-gray-100 text-center">
          <div><p class="text-xs text-gray-400">السعر</p><p class="font-bold text-sm text-primary">${formatPrice(d.price)}</p></div>
          <div><p class="text-xs text-gray-400">تقييم</p><p class="font-bold text-sm">⭐ ${d.rating}</p></div>
          <div><p class="text-xs text-gray-400">حجوزات</p><p class="font-bold text-sm">${bookings.length}</p></div>
          <div><p class="text-xs text-gray-400">إيرادات</p><p class="font-bold text-sm text-success">${formatPrice(revenue)}</p></div>
        </div>
        <div class="flex gap-2 mt-3">
          <button onclick="toggleDoctorVerified('${d.id}')" class="btn-secondary text-xs flex-1">${d.verified ? 'إلغاء التوثيق' : '✓ توثيق'}</button>
          <button onclick="toggleDoctorFeatured('${d.id}')" class="btn-secondary text-xs flex-1">${d.featured ? 'إلغاء التمييز' : '⭐ تمييز'}</button>
        </div>
      </div>
    `);
  }
  list.innerHTML = cards.join('');
}

// ---- Toggle Doctor Verified/Featured ----
async function toggleDoctorVerified(doctorId) {
  const db = await SahatnaDB.load();
  const doctor = db.doctors.find((d) => d.id === doctorId);
  if (!doctor) return;
  await SahatnaDB.updateDoctor(doctorId, { verified: !doctor.verified });
  await renderAdminDoctors();
  showToast(doctor.verified ? 'تم إلغاء توثيق الطبيب' : 'تم توثيق الطبيب', 'success');
}

async function toggleDoctorFeatured(doctorId) {
  const db = await SahatnaDB.load();
  const doctor = db.doctors.find((d) => d.id === doctorId);
  if (!doctor) return;
  await SahatnaDB.updateDoctor(doctorId, { featured: !doctor.featured });
  await renderAdminDoctors();
  showToast(doctor.featured ? 'تم إلغاء تمييز الطبيب' : 'تم تمييز الطبيب', 'success');
}

// ---- Export All Bookings CSV ----
async function exportAllBookingsCSV() {
  const db = await SahatnaDB.load();
  if (db.bookings.length === 0) { showToast('لا توجد حجوزات للتصدير', 'info'); return; }
  const headers = ['رقم الحجز', 'المريض', 'الهاتف', 'الطبيب', 'التخصص', 'العيادة', 'المدينة', 'التاريخ', 'الوقت', 'الخدمة', 'السعر', 'الحالة'];
  const rows = db.bookings.map((b) => {
    const doctor = db.doctors.find((d) => d.id === b.doctorId);
    const specialty = doctor ? db.specialties.find((s) => s.id === doctor.specialtyId) : null;
    const clinic = db.clinics.find((c) => c.id === b.clinicId);
    const city = clinic ? db.cities.find((c) => c.id === clinic.cityId) : null;
    const timeParts = b.time.split(':').map(Number);
    return [b.id, b.patientName, b.patientPhone, doctor ? doctor.name : '', specialty ? specialty.name : '', clinic ? clinic.name : '', city ? city.name : '', b.date, SahatnaDB.formatTime(timeParts[0], timeParts[1]), b.service, b.price, b.status];
  });
  const csv = [headers, ...rows].map((row) => row.map(escapeCSVCell).join(',')).join('\n');
  const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `تقرير_شامل_${new Date().toISOString().slice(0, 10)}.csv`;
  link.click();
  URL.revokeObjectURL(url);
  showToast('تم تصدير التقرير بنجاح', 'success');
}

async function renderAdminBookings() {
  const db = await SahatnaDB.load();
  const list = document.getElementById('adminBookingsList');
  if (db.bookings.length === 0) { list.innerHTML = `<div class="empty-state"><div class="empty-state-icon">📅</div><p class="text-gray-400">لا توجد حجوزات بعد</p></div>`; return; }
  const bookings = [...db.bookings].sort((a, b) => (b.date + b.time > a.date + a.time ? 1 : -1));
  list.innerHTML = bookings.map((b) => {
    const doctor = db.doctors.find((d) => d.id === b.doctorId);
    const clinic = db.clinics.find((c) => c.id === b.clinicId);
    const specialty = doctor ? db.specialties.find((s) => s.id === doctor.specialtyId) : null;
    const dayName = SahatnaDB.getDayName(new Date(b.date + 'T00:00:00').getDay());
    const timeParts = b.time.split(':').map(Number);
    return `
      <div class="booking-item status-${b.status}">
        <div class="flex items-start justify-between gap-3 flex-wrap">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1">
              <span class="font-bold text-gray-800">${escapeHTML(b.patientName)}</span>
              ${getBookingStatusBadge(b.status)}
            </div>
            <div class="text-sm text-gray-500 space-y-1">
              <p>👨‍⚕️ ${escapeHTML(doctor ? doctor.name : '')} - ${escapeHTML(specialty ? specialty.name : '')}</p>
              <p>🏥 ${escapeHTML(clinic ? clinic.name : '')}</p>
              <p>📅 ${dayName} ${b.date} • ⏰ ${SahatnaDB.formatTime(timeParts[0], timeParts[1])}</p>
              <p>📞 ${escapeHTML(b.patientPhone)} • 💰 ${formatPrice(b.price)}</p>
            </div>
          </div>
        </div>
      </div>
    `;
  }).join('');
}

async function renderAdminSpecialties() {
  const db = await SahatnaDB.load();
  const list = document.getElementById('adminSpecialtiesList');
  list.innerHTML = db.specialties.map((sp) => {
    const count = db.doctors.filter((d) => d.specialtyId === sp.id).length;
    return `<div class="flex items-center justify-between bg-gray-50 rounded-lg p-3 border border-gray-200"><div class="flex items-center gap-3"><span class="text-2xl">${escapeHTML(sp.icon)}</span><div><p class="font-semibold text-gray-700">${escapeHTML(sp.name)}</p><p class="text-xs text-gray-400">${escapeHTML(sp.nameEn)}</p></div></div><span class="badge badge-primary">${count} طبيب</span></div>`;
  }).join('');
}

async function renderAdminCities() {
  const db = await SahatnaDB.load();
  const list = document.getElementById('adminCitiesList');
  list.innerHTML = db.cities.map((city) => {
    const clinics = db.clinics.filter((c) => c.cityId === city.id && c.status === 'approved').length;
    return `<div class="flex items-center justify-between bg-gray-50 rounded-lg p-3 border border-gray-200"><div class="flex items-center gap-3"><span class="text-2xl">📍</span><p class="font-semibold text-gray-700">${escapeHTML(city.name)}</p></div><span class="badge badge-primary">${clinics} عيادة</span></div>`;
  }).join('');
}

async function renderAdminAnalytics() {
  const db = await SahatnaDB.load();
  const container = document.getElementById('adminAnalytics');
  const specialtyStats = [];
  for (const sp of db.specialties) {
    const doctorIds = db.doctors.filter((d) => d.specialtyId === sp.id).map((d) => d.id);
    const bookings = db.bookings.filter((b) => doctorIds.includes(b.doctorId)).length;
    specialtyStats.push({ ...sp, bookings });
  }
  specialtyStats.sort((a, b) => b.bookings - a.bookings);
  const doctorStats = [];
  for (const d of db.doctors) {
    const bookings = await SahatnaDB.getBookingsByDoctor(d.id);
    const completed = bookings.filter((b) => b.status === 'completed').length;
    const revenue = bookings.filter((b) => b.status === 'completed').reduce((s, b) => s + b.price, 0);
    doctorStats.push({ ...d, totalBookings: bookings.length, completed, revenue });
  }
  doctorStats.sort((a, b) => b.totalBookings - a.totalBookings);
  const clinicStats = [];
  for (const c of db.clinics.filter((c) => c.status === 'approved')) {
    const bookings = await SahatnaDB.getBookingsByClinic(c.id);
    const revenue = bookings.filter((b) => b.status === 'completed').reduce((s, b) => s + b.price, 0);
    clinicStats.push({ ...c, totalBookings: bookings.length, revenue });
  }
  clinicStats.sort((a, b) => b.totalBookings - a.totalBookings);
  const maxSpBookings = Math.max(...specialtyStats.map((s) => s.bookings), 1);
  const maxDocBookings = Math.max(...doctorStats.map((d) => d.totalBookings), 1);
  const maxClinicBookings = Math.max(...clinicStats.map((c) => c.totalBookings), 1);
  container.innerHTML = `
    <div class="stat-card">
      <h4 class="font-bold text-gray-800 mb-4">أكثر التخصصات طلباً</h4>
      <div class="space-y-3">
        ${specialtyStats.slice(0, 5).map((sp) => { const pct = (sp.bookings / maxSpBookings) * 100; return `<div><div class="flex items-center justify-between mb-1"><span class="text-sm font-semibold">${escapeHTML(sp.icon)} ${escapeHTML(sp.name)}</span><span class="text-sm text-gray-500">${sp.bookings} حجز</span></div><div class="w-full bg-gray-100 rounded-full h-2"><div class="bg-primary h-2 rounded-full transition-all" style="width: ${pct}%"></div></div></div>`; }).join('')}
      </div>
    </div>
    <div class="stat-card">
      <h4 class="font-bold text-gray-800 mb-4">أكثر الأطباء حجوزاً</h4>
      <div class="space-y-3">
        ${doctorStats.slice(0, 5).map((d) => { const pct = (d.totalBookings / maxDocBookings) * 100; return `<div><div class="flex items-center justify-between mb-1"><span class="text-sm font-semibold">👨‍⚕️ ${escapeHTML(d.name)}</span><span class="text-sm text-gray-500">${d.totalBookings} حجز • ${formatPrice(d.revenue)}</span></div><div class="w-full bg-gray-100 rounded-full h-2"><div class="bg-success h-2 rounded-full transition-all" style="width: ${pct}%"></div></div></div>`; }).join('')}
      </div>
    </div>
    <div class="stat-card">
      <h4 class="font-bold text-gray-800 mb-4">أكثر العيادات نشاطاً</h4>
      <div class="space-y-3">
        ${clinicStats.slice(0, 5).map((c) => { const pct = (c.totalBookings / maxClinicBookings) * 100; const city = db.cities.find((ci) => ci.id === c.cityId); return `<div><div class="flex items-center justify-between mb-1"><span class="text-sm font-semibold">🏥 ${escapeHTML(c.name)} - ${escapeHTML(city ? city.name : '')}</span><span class="text-sm text-gray-500">${c.totalBookings} حجز • ${formatPrice(c.revenue)}</span></div><div class="w-full bg-gray-100 rounded-full h-2"><div class="bg-info h-2 rounded-full transition-all" style="width: ${pct}%"></div></div></div>`; }).join('')}
      </div>
    </div>
    <div class="stat-card">
      <h4 class="font-bold text-gray-800 mb-4">ملخص الأداء</h4>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-center">
        <div><p class="text-3xl font-bold text-primary">${db.doctors.length}</p><p class="text-sm text-gray-400">طبيب</p></div>
        <div><p class="text-3xl font-bold text-info">${db.clinics.filter((c) => c.status === 'approved').length}</p><p class="text-sm text-gray-400">عيادة نشطة</p></div>
        <div><p class="text-3xl font-bold text-success">${db.bookings.length}</p><p class="text-sm text-gray-400">حجز</p></div>
        <div><p class="text-3xl font-bold text-warning">${new Set(db.bookings.map((b) => b.patientPhone)).size}</p><p class="text-sm text-gray-400">مريض</p></div>
      </div>
    </div>
  `;
}

document.addEventListener('DOMContentLoaded', () => {
  if (SahatnaDB.isSupabaseEnabled()) {
    document.getElementById('adminDemoCredentials')?.classList.add('hidden');
  }
  checkAdminSession().catch((error) => {
    console.error('Admin session check failed:', error);
    showToast('تعذر التحقق من جلسة الإدارة', 'error');
  });
});
