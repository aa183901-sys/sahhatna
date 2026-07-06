/**
 * صحتنا - Unified Database Layer
 * Automatically uses Supabase if configured, otherwise falls back to localStorage.
 * This wraps SahatnaDB and adds Supabase support with the same API.
 */

const SahatnaAPI = (async function () {
  const useSupabase = SUPABASE_CONFIG.enabled;
  let sb = null;

  if (useSupabase) {
    sb = await initSupabase();
  }

  // ---- Helpers -----------------------------------------------------------
  function formatTime(h, m) {
    const period = h >= 12 ? 'م' : 'ص';
    let h12 = h % 12;
    if (h12 === 0) h12 = 12;
    return `${h12}:${String(m).padStart(2, '0')} ${period}`;
  }

  function getDayName(day) {
    return ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'][day];
  }

  function getMonthName(month) {
    return ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'][month];
  }

  // ---- Supabase Implementation ------------------------------------------
  const SupabaseImpl = {
    async getSpecialties() {
      const { data } = await sb.from('specialties').select('*');
      return data || [];
    },
    async getCities() {
      const { data } = await sb.from('cities').select('*');
      return data || [];
    },
    async getClinics() {
      const { data } = await sb.from('clinics').select('*');
      return data || [];
    },
    async getDoctors() {
      const { data } = await sb.from('doctors').select('*');
      return data || [];
    },
    async getDoctor(id) {
      const { data } = await sb.from('doctors').select('*').eq('id', id).single();
      return data;
    },
    async getSchedule(doctorId) {
      const { data } = await sb.from('schedules').select('*').eq('doctor_id', doctorId);
      if (!data || data.length === 0) return null;
      return {
        doctorId,
        slots: data.map((s) => ({ day: s.day, start: s.start_time, end: s.end_time })),
        slotDuration: data[0].slot_duration || 30,
      };
    },
    async getReviews(doctorId) {
      const { data } = await sb.from('reviews').select('*').eq('doctor_id', doctorId);
      return data || [];
    },
    async getAppointmentsByClinic(clinicId) {
      const { data } = await sb.from('appointments').select('*').eq('clinic_id', clinicId).order('date', { ascending: true });
      return data || [];
    },
    async getAppointmentsByDoctor(doctorId) {
      const { data } = await sb.from('appointments').select('*').eq('doctor_id', doctorId).order('date', { ascending: true });
      return data || [];
    },
    async getAllAppointments() {
      const { data } = await sb.from('appointments').select('*').order('created_at', { ascending: false });
      return data || [];
    },
    async createAppointment(data) {
      const { data: apt, error } = await sb.from('appointments').insert({
        doctor_id: data.doctorId,
        clinic_id: data.clinicId,
        patient_name: data.patientName,
        patient_phone: data.patientPhone,
        patient_age: data.patientAge,
        patient_notes: data.patientNotes,
        date: data.date,
        time: data.time,
        service: data.service,
        price: data.price,
        status: 'confirmed',
        payment_method: 'clinic',
      }).select().single();

      if (error) throw error;

      // Create reminder
      const doctor = await this.getDoctor(data.doctorId);
      const clinic = (await this.getClinics()).find((c) => c.id === data.clinicId);
      await sb.from('reminders').insert({
        appointment_id: apt.id,
        patient_name: data.patientName,
        patient_phone: data.patientPhone,
        doctor_name: doctor.name,
        clinic_name: clinic.name,
        date: data.date,
        time: data.time,
        sent: false,
      });

      return apt;
    },
    async updateAppointmentStatus(id, status) {
      const { data } = await sb.from('appointments').update({ status }).eq('id', id).select().single();
      return data;
    },
    async updateSchedule(doctorId, slots, slotDuration) {
      // Delete existing
      await sb.from('schedules').delete().eq('doctor_id', doctorId);
      // Insert new
      if (slots.length > 0) {
        const rows = slots.map((s) => ({
          doctor_id: doctorId,
          day: s.day,
          start_time: s.start,
          end_time: s.end,
          slot_duration: slotDuration,
        }));
        await sb.from('schedules').insert(rows);
      }
    },
    async approveClinic(id) {
      const { data } = await sb.from('clinics').update({ status: 'approved' }).eq('id', id).select().single();
      return data;
    },
    async rejectClinic(id) {
      const { data } = await sb.from('clinics').update({ status: 'rejected' }).eq('id', id).select().single();
      return data;
    },
    async addClinic(data) {
      const { data: clinic } = await sb.from('clinics').insert({
        name: data.name,
        city_id: data.cityId,
        area: data.area,
        address: data.address,
        phone: data.phone,
        lat: data.lat || 0,
        lng: data.lng || 0,
        status: 'pending',
      }).select().single();
      return clinic;
    },
    async clinicLogin(username, password) {
      const { data: user } = await sb.from('clinic_users').select('*').eq('username', username).eq('password', password).single();
      if (!user) return null;
      const { data: clinic } = await sb.from('clinics').select('*').eq('id', user.clinic_id).single();
      return { user, clinic };
    },
    async adminLogin(username, password) {
      const { data } = await sb.from('admin_users').select('*').eq('username', username).eq('password', password).single();
      return data || null;
    },
    async getReminders() {
      const { data } = await sb.from('reminders').select('*').eq('sent', false);
      return data || [];
    },
    async markReminderSent(id) {
      const { data } = await sb.from('reminders').update({ sent: true, sent_at: new Date().toISOString() }).eq('id', id).select().single();
      return data;
    },
    async getStats() {
      const [doctors, clinics, apts] = await Promise.all([
        sb.from('doctors').select('*'),
        sb.from('clinics').select('*'),
        sb.from('appointments').select('*'),
      ]);
      const d = doctors.data || [];
      const c = clinics.data || [];
      const a = apts.data || [];
      return {
        totalDoctors: d.length,
        totalClinics: c.length,
        approvedClinics: c.filter((x) => x.status === 'approved').length,
        pendingClinics: c.filter((x) => x.status === 'pending').length,
        totalBookings: a.length,
        confirmedBookings: a.filter((x) => x.status === 'confirmed').length,
        completedBookings: a.filter((x) => x.status === 'completed').length,
        cancelledBookings: a.filter((x) => x.status === 'cancelled').length,
        totalRevenue: a.filter((x) => x.status === 'completed').reduce((s, x) => s + x.price, 0),
        totalPatients: new Set(a.map((x) => x.patient_phone)).size,
      };
    },
  };

  // ---- Slot generation (shared) -----------------------------------------
  async function getAvailableSlots(doctorId, dateStr) {
    const schedule = useSupabase && sb ? await SupabaseImpl.getSchedule(doctorId) : SahatnaDB.getSchedule(doctorId);
    if (!schedule) return [];

    const date = new Date(dateStr + 'T00:00:00');
    const day = date.getDay();
    const daySlot = schedule.slots.find((s) => s.day === day);
    if (!daySlot) return [];

    const slots = [];
    const [sh, sm] = daySlot.start.split(':').map(Number);
    const [eh, em] = daySlot.end.split(':').map(Number);
    const startMin = sh * 60 + sm;
    const endMin = eh * 60 + em;
    const duration = schedule.slotDuration || 30;

    const now = new Date();
    const isToday = dateStr === now.toISOString().slice(0, 10);
    const nowMin = now.getHours() * 60 + now.getMinutes();

    for (let t = startMin; t + duration <= endMin; t += duration) {
      if (isToday && t <= nowMin) continue;
      const h = Math.floor(t / 60);
      const m = t % 60;
      slots.push({
        time: `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`,
        label: formatTime(h, m),
      });
    }

    // Filter booked slots
    let booked = [];
    if (useSupabase && sb) {
      const { data } = await sb.from('appointments').select('time').eq('doctor_id', doctorId).eq('date', dateStr).neq('status', 'cancelled');
      booked = (data || []).map((b) => b.time);
    } else {
      const db = SahatnaDB.load();
      booked = db.bookings.filter((b) => b.doctorId === doctorId && b.date === dateStr && b.status !== 'cancelled').map((b) => b.time);
    }
    return slots.filter((s) => !booked.includes(s.time));
  }

  async function getAvailableDays(doctorId, daysAhead = 14) {
    const result = [];
    const today = new Date();
    for (let i = 0; i < daysAhead; i++) {
      const d = new Date(today);
      d.setDate(d.getDate() + i);
      const dateStr = d.toISOString().slice(0, 10);
      const slots = await getAvailableSlots(doctorId, dateStr);
      result.push({
        date: dateStr,
        dayName: getDayName(d.getDay()),
        dayNumber: d.getDate(),
        monthName: getMonthName(d.getMonth()),
        slotsCount: slots.length,
        slots,
      });
    }
    return result;
  }

  // ---- Return unified API ------------------------------------------------
  if (useSupabase && sb) {
    console.log('🔄 Using Supabase database');
    return {
      mode: 'supabase',
      ...SupabaseImpl,
      getAvailableSlots,
      getAvailableDays,
      formatTime,
      getDayName,
      getMonthName,
    };
  }

  console.log('🔄 Using localStorage database (demo mode)');
  return {
    mode: 'local',
    // Wrap localStorage methods to support async callers
    getSpecialties: () => SahatnaDB.load().specialties,
    getCities: () => SahatnaDB.load().cities,
    getClinics: () => SahatnaDB.load().clinics,
    getDoctor: (id) => SahatnaDB.getDoctor(id),
    getSchedule: (doctorId) => SahatnaDB.getSchedule(doctorId),
    getReviews: (doctorId) => SahatnaDB.load().reviews.filter((r) => r.doctorId === doctorId),
    getAppointmentsByClinic: (clinicId) => SahatnaDB.getBookingsByClinic(clinicId),
    getAppointmentsByDoctor: (doctorId) => SahatnaDB.getBookingsByDoctor(doctorId),
    getAllAppointments: () => SahatnaDB.load().bookings,
    createAppointment: (data) => SahatnaDB.createBooking(data),
    updateAppointmentStatus: (id, status) => SahatnaDB.updateBookingStatus(id, status),
    updateSchedule: (doctorId, slots, dur) => SahatnaDB.updateSchedule(doctorId, slots, dur),
    approveClinic: (id) => SahatnaDB.approveClinic(id),
    rejectClinic: (id) => SahatnaDB.rejectClinic(id),
    addClinic: (data) => SahatnaDB.addClinic(data),
    clinicLogin: (u, p) => SahatnaDB.clinicLogin(u, p),
    adminLogin: (u, p) => SahatnaDB.adminLogin(u, p),
    getReminders: () => SahatnaDB.getPendingReminders(),
    markReminderSent: (id) => SahatnaDB.markReminderSent(id),
    getStats: () => SahatnaDB.getStats(),
    getAvailableSlots,
    getAvailableDays,
    formatTime,
    getDayName,
    getMonthName,
  };
})();