import { defineServerMessages } from "@/lib/i18n/server/define";

export const serverAuthMessages = defineServerMessages(
  {
    "auth.request.demo": "For Apple review, use the demo code from App Review Information.",
    "auth.request.sent": "Verification code sent",
    "auth.error.invalidCode": "The code is invalid or has expired",
    "auth.error.deactivated": "Account is deactivated",
    "auth.error.agreementRequired": "Accept the current user agreement and consent to personal data processing",
    "auth.error.invalidRequest": "Check the email address and verification details",
    "profile.error.incompleteForMatching": "Finish your profile — sport, level, and city — before inviting other players",
    "auth.error.unavailable": "Sign-in is temporarily unavailable. Please try again later.",
    "auth.error.appleInvalid": "Apple sign-in could not be verified. Start the Apple sign-in flow again.",
    "auth.error.appleEmailRequired": "Apple did not provide an email address for this new account. Try again or sign in with email.",
    "auth.error.appleUnavailable": "Apple sign-in is temporarily unavailable. Please try again later.",
    "auth.error.googleInvalid": "Google sign-in could not be verified. Try signing in with Google again.",
    "auth.error.googleEmailRequired": "Google did not confirm an email address for this new account. Try again or sign in with email.",
    "auth.error.googleUnavailable": "Google sign-in is temporarily unavailable. Please try again later.",
    "auth.email.subject": "Your TennisSearch sign-in code",
    "auth.email.heading": "Your TennisSearch sign-in code:",
    "auth.email.expiry": "The code is valid for 10 minutes. If you did not request it, you can ignore this email."
  },
  {
    "auth.request.demo": "Для проверки Apple используйте demo-код из App Review Information.",
    "auth.request.sent": "Код подтверждения отправлен",
    "auth.error.invalidCode": "Неверный или просроченный код",
    "auth.error.deactivated": "Аккаунт деактивирован",
    "auth.error.agreementRequired": "Примите актуальное пользовательское соглашение и согласие на обработку персональных данных",
    "auth.error.invalidRequest": "Проверьте email и данные подтверждения",
    "profile.error.incompleteForMatching": "Заполните профиль — вид спорта, уровень и город, — чтобы приглашать других игроков",
    "auth.error.unavailable": "Вход временно недоступен. Попробуйте ещё раз позже.",
    "auth.error.appleInvalid": "Не удалось подтвердить вход через Apple. Запустите вход через Apple ещё раз.",
    "auth.error.appleEmailRequired": "Apple не передал email для нового аккаунта. Попробуйте ещё раз или войдите по email.",
    "auth.error.appleUnavailable": "Вход через Apple временно недоступен. Попробуйте ещё раз позже.",
    "auth.error.googleInvalid": "Не удалось подтвердить вход через Google. Попробуйте войти через Google ещё раз.",
    "auth.error.googleEmailRequired": "Google не подтвердил email для нового аккаунта. Попробуйте ещё раз или войдите по email.",
    "auth.error.googleUnavailable": "Вход через Google временно недоступен. Попробуйте ещё раз позже.",
    "auth.email.subject": "Код входа в TennisSearch",
    "auth.email.heading": "Код входа в TennisSearch:",
    "auth.email.expiry": "Код действует 10 минут. Если вы не запрашивали вход, просто проигнорируйте это письмо."
  }
);
