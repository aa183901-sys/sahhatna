/**
 * صحتنا - My Bookings Logic
 * Patient can view their bookings by phone number, cancel upcoming bookings,
 * and leave reviews for completed visits.
 */

// ---- State ---------------------------------------------------------------
let currentPhone = null;
let allBookings = [];
let currentFilter = 'all';

// ---- Utilities -----------------------------------------------------------
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
  }, 3000);
}

function formatPrice(price) {
  return new Intl.NumberFormat('ar-IQ').format(price) + ' د.ع';
}

function getStatusBadge(status) {
  const badges = {
    confirmed: '<span class="badge badge-info">مؤكد</span>',
    completed: '<span class="badge badge-success">مكتمل</span>',
    cancelled: '<span class="badge badge-danger">ملغي</span>',
    no_show: '<span class="badge badge-warning">لم يحضر</span>',
  };
  return badges[status] || badges.confirmed;
}

function getServiceLabel(service) {
  const labels = { clinic: 'زيارة عيادة', video: 'استشارة فيديو', home: 'زيارة منزلية' };
  return labels[service] || service;
}

function getServiceIcon(service) {
  const icons = { clinic: '🏥', video: '📹', home: '🏠' };
  return icons[service] || '🏥';
}

function isUpcoming(booking) {
  if (booking.status !== 'confirmed') return false;
  const now = new Date().toISOString().slice(0, 10);
  return booking.date >= now;
}

// ---- Auth ----------------------------------------------------------------
async function handleLogin(event) {
  event.preventDefault();
  const phone = document.getElementById('loginPhone').value.trim();
  const cleanPhone = phone.replace(/[\s\-]/g, '');

  if (!/^07\d{9}$/.test(cleanPhone)) {
    showToast('رقم الهاتف غير صحيح. يجب أن يبدأ بـ 07 ويتكون من 11 رقماً', 'error');
    return;
  }

  currentPhone = cleanPhone;
  sessionStorage.setItem('sahatna_patient_phone', cleanPhone);
  await showBookings();
  showToast('تم تسجيل الدخول', 'success');
}

function logout() {
  sessionStorage.removeItem('sahatna_patient_phone');
  currentPhone = null;
  allBookings = [];
  document.getElementById('bookingsSection').classList.add('hidden');
  document.getElementById('loginSection').classList.remove('hidden');
  document.getElementById('loginPhone').value = '';
  showToast('تم تسجيل الخروج', 'info');
}

async function checkSession() {
  const saved = sessionStorage.getItem('sahatna_patient_phone');
  if (saved) {
    currentPhone = saved;
    await showBookings();
  }
}

// ---- Show Bookings -------------------------------------------------------
async function showBookings() {
  document.getElementById('loginSection').classList.add('hidden');
  document.getElementById('bookingsSection').classList.remove('hidden');
  document.getElementById('phoneDisplay').textContent = '📞 ' + currentPhone;
  await loadBookings();
}

async function loadBookings() {
  const list = document.getElementById('bookingsList');
  list.innerHTML = '<div class="text-center py-8"><div class="spinner mx-auto"></div><p class="text-gray-400 mt-3">جاري تحميل الحجوزات...</p></div>';

  try {
    allBookings = await SahatnaDB.getBookingsByPhone(currentPhone);
    renderStats();
    renderBookings();
  } catch (error) {
    console.error('Load bookings error:', error);
    list.innerHTML = '<div class="empty-state"><div class="empty-state-icon">⚠️</div><p class="text-gray-400">حدث خطأ أثناء تحميل الحجوزات</p></div>';
  }
}

function renderStats() {
  const upcoming = allBookings.filter(isUpcoming).length;
  const completed = allBookings.filter((b) => b.status === 'completed').length;
  const cancelled = allBookings.filter((b) => b.status === 'cancelled').length;
  document.getElementById('statUpcoming').textContent = upcoming;
  document.getElementById('statCompleted').textContent = completed;
  document.getElementById('statCancelled').textContent = cancelled;
}

function setFilter(filter) {
  currentFilter = filter;
  document.querySelectorAll('.filter-tab').forEach((tab) => tab.classList.remove('active'));
  document.querySelector(`[data-filter="${filter}"]`).classList.add('active');
  renderBookings();
}

async function renderBookings() {
  const list = document.getElementById('bookingsList');
  let filtered = allBookings;

  if (currentFilter === 'upcoming') filtered = allBookings.filter(isUpcoming);
  else if (currentFilter === 'completed') filtered = allBookings.filter((b) => b.status === 'completed');
  else if (currentFilter === 'cancelled') filtered = allBookings.filter((b) => b.status === 'cancelled');

  if (filtered.length === 0) {
    list.innerHTML = `
      <div class="empty-state">
        <div class="empty-state-icon">📋</div>
        <h4 class="text-lg font-bold text-gray-500 mb-2">لا توجد حجوزات</h4>
        <p class="text-gray-400 mb-4">${currentFilter === 'all' ? 'لم تقم بأي حجز بعد' : 'لا توجد حجوزات في هذا التصنيف'}</p>
        <a href="index.html" class="btn-primary inline-block">احجز موعداً جديداً</a>
      </div>
    `;
    return;
  }

  const db = await SahatnaDB.load();
  const cards = [];

  for (const b of filtered) {
    const doctor = db.doctors.find((d) => d.id === b.doctorId);
    const specialty = doctor ? db.specialties.find((s) => s.id === doctor.specialtyId) : null;
    const clinic = db.clinics.find((c) => c.id === b.clinicId);
    const dayName = SahatnaDB.getDayName(new Date(b.date + 'T00:00:00').getDay());
    const timeParts = b.time.split(':').map(Number);
    const upcoming = isUpcoming(b);
    const alreadyReviewed = await SahatnaDB.hasReviewed(b.id);

    cards.push(`
      <div class="booking-item status-${b.status} animate-fade-in">
        <div class="flex items-start justify-between gap-3 flex-wrap">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-2">
              ${doctor ? `<img src="${doctor.photo}" class="w-12 h-12 rounded-xl object-cover" />` : ''}
              <div>
                <h4 class="font-bold text-gray-800">${doctor ? doctor.name : 'طبيب غير معروف'}</h4>
                <p class="text-sm text-primary">${specialty ? specialty.name : ''}</p>
              </div>
              ${getStatusBadge(b.status)}
            </div>
            <div class="text-sm text-gray-500 space-y-1">
              <p>📅 ${dayName} ${b.date} • ⏰ ${SahatnaDB.formatTime(timeParts[0], timeParts[1])}</p>
              <p>🏥 ${clinic ? clinic.name : ''}</p>
              <p>📍 ${clinic ? clinic.area : ''}</p>
              <p>${getServiceIcon(b.service)} ${getServiceLabel(b.service)} • 💰 ${formatPrice(b.price)}</p>
              ${b.patientNotes ? `<p class="text-gray-400 italic">📝 ${b.patientNotes}</p>` : ''}
            </div>
          </div>
          <div class="flex flex-col gap-2 flex-shrink-0">
            ${upcoming ? `
              <button onclick="cancelMyBooking('${b.id}')" class="btn-danger text-xs">✕ إلغاء الحجز</button>
              ${clinic ? `<button onclick="callClinic('${clinic.phone}')" class="btn-secondary text-xs">📞 اتصل بالعيادة</button>` : ''}
            ` : ''}
            ${b.status === 'completed' && !alreadyReviewed ? `
              <button onclick="openReviewModal('${b.id}', '${doctor ? doctor.id : ''}', '${doctor ? doctor.name.replace(/'/g, "\\'") : ''}')" class="btn-primary text-xs">⭐ قيّم الطبيب</button>
            ` : ''}
            ${b.status === 'completed' && alreadyReviewed ? `
              <span class="text-xs text-success font-semibold">✓ تم التقييم</span>
            ` : ''}
            ${b.status === 'cancelled' ? `
              <span class="text-xs text-danger font-semibold">✕ ملغي</span>
            ` : ''}
            ${b.status === 'no_show' ? `
              <span class="text-xs text-warning font-semibold">🚫 لم يحضر</span>
            ` : ''}
          </div>
        </div>
      </div>
    `);
  }
  list.innerHTML = cards.join('');
}

// ---- Cancel Booking ------------------------------------------------------
async function cancelMyBooking(bookingId) {
  if (!confirm('هل أنت متأكد من إلغاء هذا الحجز؟\n\nملاحظة: يفضل الإلغاء قبل الموعد بـ 24 ساعة على الأقل.')) return;

  try {
    await SahatnaDB.cancelBooking(bookingId);
    await loadBookings();
    showToast('تم إلغاء الحجز بنجاح', 'success');
  } catch (error) {
    console.error('Cancel error:', error);
    showToast('حدث خطأ أثناء إلغاء الحجز', 'error');
  }
}

function callClinic(phone) {
  window.location.href = 'tel:' + phone;
}

// ---- Review Modal --------------------------------------------------------
function openReviewModal(bookingId, doctorId, doctorName) {
  const modal = document.getElementById('reviewModal');
  modal.classList.remove('hidden');
  modal.innerHTML = `
    <div class="modal-overlay" onclick="if(event.target===this) closeReviewModal()">
      <div class="modal-content">
        <div class="bg-primary text-white p-5 rounded-t-2xl flex items-center justify-between">
          <div>
            <h3 class="text-lg font-bold">⭐ تقييم الطبيب</h3>
            <p class="text-teal-100 text-sm mt-1">${doctorName}</p>
          </div>
          <button onclick="closeReviewModal()" class="text-white/80 hover:text-white text-2xl">✕</button>
        </div>
        <div class="p-6">
          <form onsubmit="submitReview(event, '${bookingId}', '${doctorId}')">
            <div class="text-center mb-6">
              <label class="block text-sm font-semibold text-gray-600 mb-3">تقييمك</label>
              <div class="flex justify-center gap-2" id="starRating">
                ${[1, 2, 3, 4, 5].map((n) => `
                  <button type="button" onclick="setRating(${n})" id="star-${n}" class="text-4xl text-gray-300 hover:text-warning transition star-btn">★</button>
                `).join('')}
              </div>
              <input type="hidden" id="reviewRating" value="0" required />
              <p class="text-xs text-gray-400 mt-2" id="ratingLabel">اختر التقييم</p>
            </div>
            <div class="mb-4">
              <label class="block text-sm font-semibold text-gray-600 mb-1">تعليقك (اختياري)</label>
              <textarea id="reviewComment" rows="3" placeholder="شاركنا تجربتك مع الطبيب..." class="form-input"></textarea>
            </div>
            <div class="flex gap-3">
              <button type="button" onclick="closeReviewModal()" class="btn-secondary flex-1">إلغاء</button>
              <button type="submit" class="btn-primary flex-1">إرسال التقييم</button>
            </div>
          </form>
        </div>
      </div>
    </div>
  `;
}

function closeReviewModal() {
  document.getElementById('reviewModal').classList.add('hidden');
  document.getElementById('reviewModal').innerHTML = '';
}

let selectedRating = 0;
function setRating(n) {
  selectedRating = n;
  document.getElementById('reviewRating').value = n;
  const labels = ['', 'سيء جداً', 'سيء', 'مقبول', 'جيد', 'ممتاز'];
  document.getElementById('ratingLabel').textContent = labels[n];
  for (let i = 1; i <= 5; i++) {
    const star = document.getElementById('star-' + i);
    if (i <= n) {
      star.classList.remove('text-gray-300');
      star.classList.add('text-warning');
    } else {
      star.classList.remove('text-warning');
      star.classList.add('text-gray-300');
    }
  }
}

async function submitReview(event, bookingId, doctorId) {
  event.preventDefault();
  const rating = parseInt(document.getElementById('reviewRating').value);
  const comment = document.getElementById('reviewComment').value.trim();

  if (rating < 1 || rating > 5) {
    showToast('يرجى اختيار تقييم من 1 إلى 5 نجوم', 'error');
    return;
  }

  const booking = allBookings.find((b) => b.id === bookingId);
  if (!booking) {
    showToast('لم يتم العثور على الحجز', 'error');
    return;
  }

  try {
    await SahatnaDB.addReview({
      doctorId,
      appointmentId: bookingId,
      patientName: booking.patientName,
      patientPhone: booking.patientPhone,
      rating,
      comment,
    });
    closeReviewModal();
    await loadBookings();
    showToast('شكراً لك! تم إرسال تقييمك بنجاح', 'success');
  } catch (error) {
    console.error('Review error:', error);
    showToast('حدث خطأ أثناء إرسال التقييم', 'error');
  }
}

// ---- Initialize ----------------------------------------------------------
document.addEventListener('DOMContentLoaded', checkSession);