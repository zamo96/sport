import {
  ANALYTICS_CONSENT_VERSION,
  LEGAL_OPERATOR,
  PROFILE_VISIBILITY_CONSENT_VERSION
} from "@/lib/legal-contract";
import type { LegalLanguage, UserAgreementSection } from "@/lib/legal";

export type ConsentDocumentKey = "profile-visibility" | "analytics";

export type ConsentDocument = {
  language: LegalLanguage;
  title: string;
  description: string;
  version: string;
  versionLabel: string;
  operatorLabel: string;
  sections: UserAgreementSection[];
};

const OPERATOR_INN = LEGAL_OPERATOR.inn.replace(/^ИНН:\s*/, "");
const IOS_APP_URL = "https://apps.apple.com/app/id6768862885";

/**
 * Тексты отдельных согласий. Экземпляр согласия конкретного человека — строка
 * `UserConsent` с этой версией текста, выбранными сведениями, аудиторией и ФИО.
 * Меняя текст, поднимайте версию в `legal-contract.ts`.
 */
const PROFILE_VISIBILITY_RU: UserAgreementSection[] = [
  {
    title: "1. Кто дает согласие и кому",
    paragraphs: [
      "Я, пользователь НаТреню, указавший свои фамилию и имя в форме этого согласия, с контактным email моего аккаунта, свободно, своей волей и в своем интересе даю согласие на обработку моих персональных данных, разрешенных мной для распространения, в соответствии со статьей 10.1 Федерального закона от 27.07.2006 N 152-ФЗ \"О персональных данных\".",
      `Оператор: ${LEGAL_OPERATOR.legalName}, ИНН ${OPERATOR_INN}, адрес места жительства: ${LEGAL_OPERATOR.address}, email: ${LEGAL_OPERATOR.email}.`,
      "Согласие оформляется отдельно от пользовательского соглашения и других согласий. Фамилия, имя и email из формы согласия не публикуются на его основании."
    ]
  },
  {
    title: "2. Цель",
    paragraphs: [
      "Сделать выбранные мной сведения доступными другим людям для поиска спортивных партнеров: показ моей анкеты в поиске, на карте, в каталоге спортивных центров и показ моих игровых поисков."
    ]
  },
  {
    title: "3. Какие сведения я разрешаю показывать",
    paragraphs: [
      "Категория: иные персональные данные. Специальные категории и биометрические персональные данные не распространяются. Показываются только группы сведений, включенные мной на экране согласия; для выключенных групп разрешения нет."
    ],
    bullets: [
      "Анкета: имя для показа, возраст, город, район и выбранные районы игры, виды спорта и мой уровень, формат и покрытие, дни и время, когда я готов играть, отметка «ищу игру», отметка о недавней активности, приблизительное расстояние и причины совпадения, рассчитанные сервисом.",
      "Описание профиля.",
      "Фотографии профиля.",
      "Видео профиля.",
      "Точка района на карте — условная отметка города или района, а не мое местоположение.",
      "Мои игровые поиски: вид спорта, уровень, дата, время, площадка или адрес, маршрут, комментарий и статус поиска."
    ]
  },
  {
    title: "4. Кому и где",
    paragraphs: [
      "Аудитория выбирается на экране согласия: только пользователи, вошедшие в аккаунт НаТреню, либо также гости без входа. Круг зарегистрированных пользователей заранее не определен.",
      `Информационные ресурсы оператора: https://sportsearch.shop/discover, https://sportsearch.shop/play/courts, https://sportsearch.shop/play/searches, приложение НаТреню для iOS (${IOS_APP_URL}) и приложение НаТреню для Android, получающие данные с https://sportsearch.shop. Передача выполняется по информационно-телекоммуникационным сетям только на этих ресурсах.`
    ]
  },
  {
    title: "5. Условия и запреты",
    paragraphs: [
      "Я запрещаю передачу моих данных оператором за пределы перечисленных ресурсов, а также их сбор, копирование в сторонние базы и использование для рекламы неограниченным кругом лиц. Этот запрет не распространяется на получение доступа к данным на ресурсах сервиса и на обработку в государственных, общественных и иных публичных интересах, определенных законом.",
      `Иные условия и запреты я могу установить, написав на ${LEGAL_OPERATOR.email}. Оператор не вправе отказать в их установлении и публикует сведения об условиях и запретах не позднее трех рабочих дней с момента получения.`
    ]
  },
  {
    title: "6. Срок, изменение и отзыв",
    paragraphs: [
      "Согласие действует с момента нажатия кнопки «Показывать анкету» (или «Оставить анкету видимой») до его отзыва, удаления аккаунта или прекращения цели.",
      `Я могу в любой момент изменить набор сведений и аудиторию или скрыть анкету в настройках профиля, а также потребовать прекратить распространение, написав на ${LEGAL_OPERATOR.email} с указанием фамилии, имени, контакта и сведений, показ которых нужно прекратить. Согласие в соответствующей части прекращается с момента получения требования.`,
      "Отказ от этого согласия не ограничивает поиск партнеров, переписку и участие в играх: без него мои сведения получают только те участники, с которыми я взаимодействую."
    ]
  }
];

const PROFILE_VISIBILITY_EN: UserAgreementSection[] = [
  {
    title: "1. Who gives consent and to whom",
    paragraphs: [
      "I, a NaTrenyu user who has entered my surname and first name in this consent form, with the contact email of my account, freely, of my own will and in my own interest, consent to the processing of my personal data that I permit for distribution under Article 10.1 of Federal Law No. 152-FZ of July 27, 2006, On Personal Data.",
      `Operator: ${LEGAL_OPERATOR.legalName}, INN ${OPERATOR_INN}, place of residence: ${LEGAL_OPERATOR.address}, email: ${LEGAL_OPERATOR.email}.`,
      "This consent is given separately from the Terms of Use and other consents. The surname, first name, and email from this form are not published on its basis."
    ]
  },
  {
    title: "2. Purpose",
    paragraphs: [
      "To make the data I choose available to other people for finding sports partners: showing my profile in search, on the map, in the sports-venue catalog, and showing my game searches."
    ]
  },
  {
    title: "3. What data I allow to be shown",
    paragraphs: [
      "Category: other personal data. Special categories and biometric personal data are not distributed. Only the groups I switch on in the consent screen are shown; there is no permission for groups that are switched off."
    ],
    bullets: [
      "Profile card: display name, age, city, district and chosen play districts, sports and my level, format and surface, days and times I can play, the \"looking for a game\" mark, a recent-activity mark, approximate distance and match reasons calculated by the service.",
      "Profile description.",
      "Profile photos.",
      "Profile videos.",
      "District point on the map — a nominal city or district mark, not my location.",
      "My game searches: sport, level, date, time, venue or address, route, comment, and search status."
    ]
  },
  {
    title: "4. To whom and where",
    paragraphs: [
      "The audience is chosen in the consent screen: only users signed in to a NaTrenyu account, or also guests without an account. The group of registered users is not defined in advance.",
      `Operator resources: https://sportsearch.shop/discover, https://sportsearch.shop/play/courts, https://sportsearch.shop/play/searches, the NaTrenyu iOS app (${IOS_APP_URL}) and the NaTrenyu Android app, which receive data from https://sportsearch.shop. Transfer is made over information and telecommunication networks only on these resources.`
    ]
  },
  {
    title: "5. Conditions and prohibitions",
    paragraphs: [
      "I prohibit the operator from transferring my data outside the listed resources, and I prohibit an indefinite number of people from collecting it, copying it into third-party databases, or using it for advertising. This prohibition does not apply to accessing the data on the service's resources or to processing in state, public, and other public interests defined by law.",
      `I can set other conditions and prohibitions by writing to ${LEGAL_OPERATOR.email}. The operator may not refuse to set them and publishes information about them no later than three business days after receiving them.`
    ]
  },
  {
    title: "6. Term, changes, and withdrawal",
    paragraphs: [
      "The consent is valid from the moment I press \"Show my profile\" (or \"Keep my profile visible\") until it is withdrawn, the account is deleted, or the purpose ends.",
      `At any time I can change the data and audience or hide my profile in the profile settings, and I can demand that distribution stop by writing to ${LEGAL_OPERATOR.email} with my surname, first name, contact, and the data that should no longer be shown. The consent ends in the relevant part when the demand is received.`,
      "Refusing this consent does not restrict searching for partners, messaging, or joining games: without it my data is received only by the participants I interact with."
    ]
  }
];

const ANALYTICS_RU: UserAgreementSection[] = [
  {
    title: "1. Кто дает согласие и кому",
    paragraphs: [
      `Я, пользователь НаТреню, свободно и отдельно от пользовательского соглашения даю ${LEGAL_OPERATOR.legalName}, ИНН ${OPERATOR_INN}, адрес: ${LEGAL_OPERATOR.address}, email: ${LEGAL_OPERATOR.email}, согласие на необязательную аналитику использования приложения.`
    ]
  },
  {
    title: "2. Какие данные и зачем",
    paragraphs: [
      "Цель — понимать, какими функциями пользуются, находить места, где людям трудно, и улучшать приложение.",
      "Данные: идентификатор аккаунта, открытые экраны и шаги (например, шаг анкеты, вкладка поиска), совершенные действия (отправка приглашения, отклик, создание поиска, сыгранная игра, открытие уведомления), дата и время события, тип клиента (web, iOS, Android) и технические параметры события. Переписка, фото, видео и точные координаты в события не попадают. Рекламное профилирование и запись сеанса не выполняются."
    ]
  },
  {
    title: "3. Как обрабатываются",
    paragraphs: [
      "Действия: сбор, запись, систематизация, накопление, хранение, извлечение, анализ, использование, обезличивание, блокирование, удаление и уничтожение; автоматизированная обработка во внутренней системе сервиса. Внешние аналитические платформы не используются. Доступ к отчетам есть только у оператора.",
      "Срок хранения событий — не более 90 календарных дней с момента события."
    ]
  },
  {
    title: "4. Срок и отзыв",
    paragraphs: [
      `Согласие действует до отзыва или удаления аккаунта. Отозвать его можно переключателем в настройках профиля или письмом на ${LEGAL_OPERATOR.email}. После отзыва новые события не записываются, а сохраненные уничтожаются в срок до 30 дней.`,
      "Отказ от аналитики не ограничивает никакие функции приложения."
    ]
  }
];

const ANALYTICS_EN: UserAgreementSection[] = [
  {
    title: "1. Who gives consent and to whom",
    paragraphs: [
      `I, a NaTrenyu user, freely and separately from the Terms of Use, give ${LEGAL_OPERATOR.legalName}, INN ${OPERATOR_INN}, address: ${LEGAL_OPERATOR.address}, email: ${LEGAL_OPERATOR.email}, consent to optional analytics of how I use the app.`
    ]
  },
  {
    title: "2. What data and why",
    paragraphs: [
      "Purpose: to understand which features are used, find places where people struggle, and improve the app.",
      "Data: account identifier, screens and steps opened (for example, a profile step or a search tab), actions taken (sending an invitation, responding, creating a search, a played game, opening a notification), event date and time, client type (web, iOS, Android), and technical event parameters. Messages, photos, videos, and precise coordinates are never included. No advertising profiling or session recording is performed."
    ]
  },
  {
    title: "3. How it is processed",
    paragraphs: [
      "Actions: collection, recording, systematization, accumulation, storage, retrieval, analysis, use, anonymization, blocking, deletion, and destruction; automated processing in the service's internal system. No external analytics platforms are used. Only the operator can access the reports.",
      "Events are kept for no more than 90 calendar days from the event."
    ]
  },
  {
    title: "4. Term and withdrawal",
    paragraphs: [
      `The consent is valid until withdrawn or the account is deleted. You can withdraw it with the switch in the profile settings or by writing to ${LEGAL_OPERATOR.email}. After withdrawal no new events are recorded, and stored ones are destroyed within 30 days.`,
      "Refusing analytics does not restrict any app features."
    ]
  }
];

const CONSENT_DOCUMENTS: Record<ConsentDocumentKey, Record<LegalLanguage, ConsentDocument>> = {
  "profile-visibility": {
    ru: {
      language: "ru",
      title: "Согласие на показ анкеты",
      description: "Согласие на обработку персональных данных, разрешенных для распространения",
      version: PROFILE_VISIBILITY_CONSENT_VERSION,
      versionLabel: "Редакция",
      operatorLabel: "Оператор",
      sections: PROFILE_VISIBILITY_RU
    },
    en: {
      language: "en",
      title: "Consent to showing your profile",
      description: "Consent to the processing of personal data permitted for distribution",
      version: PROFILE_VISIBILITY_CONSENT_VERSION,
      versionLabel: "Version",
      operatorLabel: "Operator",
      sections: PROFILE_VISIBILITY_EN
    }
  },
  analytics: {
    ru: {
      language: "ru",
      title: "Согласие на аналитику",
      description: "Согласие на необязательную аналитику использования приложения",
      version: ANALYTICS_CONSENT_VERSION,
      versionLabel: "Редакция",
      operatorLabel: "Оператор",
      sections: ANALYTICS_RU
    },
    en: {
      language: "en",
      title: "Consent to analytics",
      description: "Consent to optional analytics of app usage",
      version: ANALYTICS_CONSENT_VERSION,
      versionLabel: "Version",
      operatorLabel: "Operator",
      sections: ANALYTICS_EN
    }
  }
};

export function getConsentDocument(key: ConsentDocumentKey, language: LegalLanguage): ConsentDocument {
  return CONSENT_DOCUMENTS[key][language];
}
