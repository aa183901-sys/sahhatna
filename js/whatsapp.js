/**
 * صحتنا - WhatsApp Reminder System
 * Opens WhatsApp with pre-filled reminder message for the patient.
 * In Iraq, WhatsApp is more effective than SMS.
 *
 * For automated sending, integrate with:
 * - WhatsApp Business API (https://business.whatsapp.com)
 * - Or Twilio WhatsApp API
 */

const WhatsAppReminder = {
  /**
   * Resolve the shared API (SahatnaAPI if loaded, otherwise SahatnaDB).
   * clinic.html loads data.js (SahatnaDB) but not db.js (SahatnaAPI),
   * so we fall back to SahatnaDB to avoid ReferenceError.
   */
  _api() {
    if (typeof SahatnaAPI !== 'undefined' && SahatnaAPI) return SahatnaAPI;
    if (typeof SahatnaDB !== 'undefined' && SahatnaDB) return SahatnaDB;
    return null;
  },

  /**
   * Generate a reminder message for an appointment
   */
  generateMessage(reminder) {
    const api = this._api();
    const dayName = api && api.getDayName
      ? api.getDayName(new Date(reminder.date + 'T00:00:00').getDay())
      : '';
    const timeParts = reminder.time.split(':').map(Number);
    const timeLabel = api && api.formatTime
      ? api.formatTime(timeParts[0], timeParts[1])
      : reminder.time;

    return `🏥 *صحتنا - تذكير موعد طبي*

مرحباً ${reminder.patientName}،

هذا تذكير بموعدك الطبي:
📅 التاريخ: ${dayName} ${reminder.date}
⏰ الوقت: ${timeLabel}
👨‍⚕️ الطبيب: ${reminder.doctorName}
🏥 العيادة: ${reminder.clinicName}

يرجى الحضور قبل الموعد بـ 10 دقائق.
لإلغاء أو تأجيل الموعد، يرجى التواصل مع العيادة.

— منصة صحتنا 🇮🇶`;
  },

  /**
   * Open WhatsApp with the reminder message
   * @param {Object} reminder - Reminder object with patient_phone, date, time, etc.
   */
  send(reminder) {
    const message = this.generateMessage(reminder);
    const phone = this.formatPhone(reminder.patientPhone);
    const url = `https://wa.me/${phone}?text=${encodeURIComponent(message)}`;
    window.open(url, '_blank');
  },

  /**
   * Send reminder to multiple patients
   */
  sendAll(reminders) {
    reminders.forEach((r, i) => {
      setTimeout(() => this.send(r), i * 2000); // 2s delay between each
    });
  },

  /**
   * Format Iraqi phone number for WhatsApp (964 prefix)
   * 07XX XXX XXXX -> 9647XXXXXXXXX
   */
  formatPhone(phone) {
    let cleaned = phone.replace(/\s+/g, '').replace(/-/g, '');
    if (cleaned.startsWith('07')) {
      cleaned = '964' + cleaned.substring(1);
    } else if (cleaned.startsWith('+964')) {
      cleaned = cleaned.substring(1);
    } else if (!cleaned.startsWith('964')) {
      cleaned = '964' + cleaned;
    }
    return cleaned;
  },

  /**
   * Generate a booking confirmation message
   */
  generateConfirmationMessage(booking, doctor, clinic) {
    const api = this._api();
    const dayName = api && api.getDayName
      ? api.getDayName(new Date(booking.date + 'T00:00:00').getDay())
      : '';
    const timeParts = booking.time.split(':').map(Number);
    const timeLabel = api && api.formatTime
      ? api.formatTime(timeParts[0], timeParts[1])
      : booking.time;

    return `🏥 *صحتنا - تأكيد حجز موعد*

تم تأكيد حجزك بنجاح!

📋 *تفاصيل الحجز:*
🔢 رقم الحجز: #${booking.id}
👤 المريض: ${booking.patientName}
👨‍⚕️ الطبيب: ${doctor.name}
🏥 العيادة: ${clinic.name}
📍 العنوان: ${clinic.address}
📅 التاريخ: ${dayName} ${booking.date}
⏰ الوقت: ${timeLabel}
💰 السعر: ${new Intl.NumberFormat('ar-IQ').format(booking.price)} د.ع
💳 الدفع: عند الحضور للعيادة

يرجى الحضور قبل الموعد بـ 10 دقائق.

— منصة صحتنا 🇮🇶`;
  },

  /**
   * Send booking confirmation via WhatsApp
   */
  sendConfirmation(booking, doctor, clinic) {
    const message = this.generateConfirmationMessage(booking, doctor, clinic);
    const phone = this.formatPhone(booking.patientPhone);
    const url = `https://wa.me/${phone}?text=${encodeURIComponent(message)}`;
    window.open(url, '_blank');
  },
};