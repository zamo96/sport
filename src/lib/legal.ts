import {
  LEGAL_OPERATOR,
  USER_AGREEMENT_EFFECTIVE_DATE,
  USER_AGREEMENT_TITLE,
  USER_AGREEMENT_VERSION
} from "@/lib/legal-contract";

export {
  ACCEPTED_USER_AGREEMENT_VERSIONS,
  LEGAL_ACCEPTANCE_ERROR,
  LEGACY_USER_AGREEMENT_VERSION,
  LEGAL_OPERATOR,
  PERSONAL_DATA_CONSENT_VERSION,
  USER_AGREEMENT_EFFECTIVE_DATE,
  USER_AGREEMENT_KEY,
  USER_AGREEMENT_TITLE,
  USER_AGREEMENT_VERSION,
  buildLatestUserAgreementPayload,
  buildUserAgreementAcceptanceRecord,
  type AcceptedUserAgreementVersion,
  type LatestUserAgreementPayload,
  type LegalAcceptanceSource
} from "@/lib/legal-contract";

export type UserAgreementSection = {
  title: string;
  paragraphs?: string[];
  bullets?: string[];
};

export type LegalLanguage = "ru" | "en";

export type UserAgreementDocument = {
  language: LegalLanguage;
  title: string;
  description: string;
  version: string;
  effectiveDate: string;
  backLabel: string;
  versionLabel: string;
  effectiveDateLabel: string;
  operatorLabel: string;
  sections: UserAgreementSection[];
};

export const PRIVACY_POLICY_VERSION = "2026-07-07";
export const PRIVACY_POLICY_EFFECTIVE_DATE = "7 июля 2026 года";
export const PRIVACY_POLICY_TITLE = "Политика конфиденциальности SportSearch";
export const PRIVACY_POLICY_SERVICE_NAME = "SportSearch";

const LEGAL_OPERATOR_DETAILS = [
  `Оператор: ${LEGAL_OPERATOR.legalName}`,
  LEGAL_OPERATOR.inn,
  LEGAL_OPERATOR.ogrn,
  LEGAL_OPERATOR.address,
  `Email для обращений: ${LEGAL_OPERATOR.email}`
].filter(Boolean);

export const PRIVACY_POLICY_SECTIONS: UserAgreementSection[] = [
  {
    title: "1. Общие положения",
    paragraphs: [
      `Настоящая Политика конфиденциальности описывает, как ${LEGAL_OPERATOR.legalName} (далее - Оператор) обрабатывает данные пользователей сервиса ${PRIVACY_POLICY_SERVICE_NAME}.`,
      "Политика применяется к iOS-приложению, сайту, PWA, API и другим интерфейсам сервиса.",
      "Используя сервис, пользователь подтверждает, что ознакомился с настоящей Политикой. Если пользователь не согласен с условиями обработки данных, он должен прекратить использование функций сервиса, требующих аккаунта."
    ]
  },
  {
    title: "2. Какие данные обрабатываются",
    bullets: [
      "Данные аккаунта: email, идентификатор Apple ID, сведения о входе и подтверждении аккаунта.",
      "Данные профиля: имя, возраст, пол, город, район, предпочитаемые районы, виды спорта, спортивный уровень, доступность, описание профиля, фото и видео, если пользователь добавляет их сам.",
      "Данные игровых сценариев: активные поиски, игровые предложения, отклики, выбранные слоты, спортивные центры, комментарии, статусы договоренностей и история действий в сервисе.",
      "Сообщения и пользовательский контент: переписка, фотоотчеты, отзывы, жалобы и иные материалы, которые пользователь отправляет через сервис.",
      "Данные устройства и использования: IP-адрес, user-agent, технические идентификаторы, push-токены, сведения об ошибках, диагностике, безопасности и базовой активности в сервисе.",
      "Географические данные: город, район, радиус поиска, выбранные спортивные центры и, если пользователь разрешит, данные местоположения или приблизительная геопозиция для поиска игроков и площадок рядом."
    ]
  },
  {
    title: "3. Цели обработки",
    bullets: [
      "создание и поддержка аккаунта;",
      "подбор спортивных партнеров, поисков и игровых предложений;",
      "показ профиля, активных поисков и игровых заявок другим пользователям в рамках функций сервиса;",
      "обмен сообщениями, согласование времени, места и состава игры;",
      "отправка сервисных уведомлений об откликах, сообщениях, игровых заявках, изменениях статуса и безопасности аккаунта;",
      "поддержка пользователей и обработка обращений;",
      "предотвращение злоупотреблений, защита пользователей и обеспечение стабильной работы сервиса;",
      "анализ качества продукта, исправление ошибок и развитие функций сервиса;",
      "выполнение требований закона и защита прав Оператора, пользователей и третьих лиц."
    ]
  },
  {
    title: "4. Что видно другим пользователям",
    paragraphs: [
      "Часть данных нужна для работы спортивного поиска и может быть показана другим пользователям. Например, имя, возраст, город, район, виды спорта, уровень, доступность, фото, видео, описание профиля, активные поиски, игровые предложения и выбранные параметры игры.",
      "Сообщения и детали конкретной договоренности видны участникам соответствующего чата, матча, поиска или игровой заявки."
    ]
  },
  {
    title: "5. Передача данных",
    paragraphs: [
      "Оператор не продает персональные данные пользователей.",
      "Данные могут передаваться техническим поставщикам, которые помогают обеспечивать работу сервиса: хостинг, хранение данных, отправка email, push-уведомления, аналитика, диагностика, безопасность и поддержка. Такие поставщики получают данные только в объеме, необходимом для выполнения своих функций.",
      "Данные также могут быть раскрыты, если это требуется законом, судебным актом, запросом уполномоченного органа или необходимо для защиты прав, безопасности и законных интересов Оператора, пользователей или третьих лиц."
    ]
  },
  {
    title: "6. Хранение и удаление",
    paragraphs: [
      "Данные хранятся столько, сколько необходимо для работы аккаунта, предоставления функций сервиса, выполнения требований закона, разрешения споров, обеспечения безопасности и защиты прав.",
      "Пользователь может обратиться к Оператору для удаления аккаунта, уточнения, блокирования или удаления персональных данных, а также для отзыва согласия на обработку данных.",
      "После удаления аккаунта отдельные сведения могут временно сохраняться, если это требуется законом, безопасностью, предотвращением злоупотреблений, бухгалтерским учетом, разрешением споров или защитой прав."
    ]
  },
  {
    title: "7. Права пользователя",
    bullets: [
      "получить информацию об обработке своих персональных данных;",
      "запросить уточнение, блокирование или удаление данных;",
      "отозвать согласие на обработку персональных данных;",
      "удалить аккаунт или обратиться за помощью с удалением;",
      "направить вопрос, жалобу или запрос по конфиденциальности на контактный email Оператора."
    ]
  },
  {
    title: "8. Дети",
    paragraphs: [
      "Сервис предназначен для пользователей от 18 лет. Если Оператор узнает, что аккаунт создан лицом младше 18 лет, такой аккаунт может быть ограничен или удален."
    ]
  },
  {
    title: "9. Безопасность",
    paragraphs: [
      "Оператор применяет организационные и технические меры для защиты данных от несанкционированного доступа, изменения, раскрытия или уничтожения. При этом ни один способ передачи или хранения данных не может быть гарантирован как полностью безопасный."
    ]
  },
  {
    title: "10. Изменения Политики",
    paragraphs: [
      "Оператор может обновлять настоящую Политику. Новая редакция размещается в сервисе с указанием версии и даты вступления в силу. Если изменения существенно влияют на права пользователей, Оператор может дополнительно уведомить пользователей доступным способом."
    ]
  },
  {
    title: "11. Контакты",
    bullets: LEGAL_OPERATOR_DETAILS
  }
];

export const USER_AGREEMENT_SECTIONS: UserAgreementSection[] = [
  {
    title: "1. Общие положения",
    paragraphs: [
      `Настоящее Пользовательское соглашение регулирует отношения между ${LEGAL_OPERATOR.legalName} (далее - Оператор) и лицом, использующим сервис ${LEGAL_OPERATOR.serviceName} через сайт, PWA, iOS-приложение, API или иные интерфейсы сервиса (далее - Пользователь).`,
      "Соглашение является публичной офертой в смысле статей 435, 437 и 438 Гражданского кодекса Российской Федерации. Регистрация, вход в аккаунт, подтверждение email, вход через Apple ID, проставление отметки о согласии или дальнейшее использование сервиса означает полный и безоговорочный акцепт Соглашения.",
      "Если Пользователь не согласен с условиями Соглашения, он обязан прекратить регистрацию и не использовать функции сервиса, требующие аккаунта."
    ]
  },
  {
    title: "2. Термины",
    bullets: [
      "Сервис - программный комплекс SportSearch для поиска спортивных партнеров, игровых заявок, переписок, уведомлений и связанных функций.",
      "Аккаунт - учетная запись Пользователя, создаваемая через email-код или Apple ID.",
      "Профиль - сведения Пользователя о имени, возрасте, городе, районе, видах спорта, уровне, доступности, фото, видео и иных данных, которые Пользователь указывает в сервисе.",
      "Контент - тексты, сообщения, фото, видео, отзывы, заявки, отклики и иные материалы, размещаемые Пользователем.",
      "Игровая заявка - предложение или поиск игры, создаваемые Пользователем для согласования спорта, времени, места и состава участников."
    ]
  },
  {
    title: "3. Предмет соглашения",
    paragraphs: [
      "Оператор предоставляет Пользователю техническую возможность создать профиль, искать спортивных партнеров, откликаться на игровые заявки, вести переписку, получать сервисные уведомления и использовать иные доступные функции.",
      "Оператор не является организатором спортивных мероприятий, тренером, медицинским консультантом, владельцем спортивных площадок или стороной договоренностей между Пользователями, если прямо не указано иное.",
      "Пользователи самостоятельно согласуют место, время, оплату площадки, правила встречи и иные условия совместной игры."
    ]
  },
  {
    title: "4. Регистрация и аккаунт",
    bullets: [
      "Регистрация доступна лицам от 18 лет. Создавая аккаунт, Пользователь подтверждает, что достиг 18 лет и обладает полной дееспособностью.",
      "Пользователь обязан указывать достоверный email и не использовать чужие Apple ID, email, имена, фото и иные данные.",
      "Пользователь отвечает за сохранность доступа к email, Apple ID, устройству и сессии в приложении.",
      "Оператор вправе отказать в регистрации, ограничить или прекратить доступ при нарушении Соглашения, закона, прав третьих лиц или правил добросовестного поведения в сервисе."
    ]
  },
  {
    title: "5. Профиль, поиск и встречи",
    bullets: [
      "Пользователь самостоятельно выбирает виды спорта, уровень, район, доступность, радиус поиска и иные параметры профиля.",
      "Алгоритмы рекомендаций используют профиль, активность, географические и игровые параметры для подбора карточек, поисков и уведомлений.",
      "Пользователь понимает, что спорт связан с физической нагрузкой и риском травм. Перед участием в игре Пользователь самостоятельно оценивает состояние здоровья, уровень подготовки и условия площадки.",
      "Оператор не гарантирует наличие подходящих партнеров, доступность спортивных площадок, явку других Пользователей и качество встреч."
    ]
  },
  {
    title: "6. Правила поведения",
    bullets: [
      "В сервисе действует нулевая терпимость к нежелательному, оскорбительному и незаконному Контенту, а также к Пользователям, которые угрожают, преследуют, унижают других лиц или иным образом злоупотребляют функциями сервиса.",
      "Запрещены угрозы, оскорбления, дискриминация, домогательства, спам, мошенничество, выдача себя за другое лицо и действия, нарушающие права других Пользователей.",
      "Запрещено размещать незаконный, вредоносный, порнографический, экстремистский, клеветнический или нарушающий чужие права Контент.",
      "Запрещено собирать, публиковать или передавать персональные данные других Пользователей без законного основания и их согласия.",
      "Запрещено вмешиваться в работу сервиса, обходить ограничения, использовать ботов, массовые выгрузки, скрейпинг или несанкционированный доступ."
    ]
  },
  {
    title: "7. Модерация и ограничения",
    paragraphs: [
      "Оператор вправе проверять жалобы, скрывать, удалять или ограничивать распространение Контента, блокировать аккаунты и технические идентификаторы, если это необходимо для соблюдения закона, защиты Пользователей, предотвращения злоупотреблений или обеспечения стабильной работы сервиса.",
      "Пользователь может пожаловаться на профиль или материалы другого Пользователя и заблокировать его доступными в сервисе средствами. После блокировки Контент заблокированного Пользователя немедленно перестает показываться заблокировавшему его Пользователю, а Оператор получает уведомление для проверки.",
      "Оператор рассматривает жалобы на нежелательный Контент и злоупотребления в течение 24 часов. При подтверждении нарушения Оператор удаляет или скрывает соответствующий Контент и прекращает доступ нарушившего Пользователя к сервису.",
      "Оператор может временно ограничить функции сервиса при технических работах, ошибках, подозрении на нарушение безопасности или по требованию закона."
    ]
  },
  {
    title: "8. Персональные данные",
    paragraphs: [
      "При регистрации и использовании сервиса Пользователь дает Оператору согласие на обработку персональных данных в соответствии с Федеральным законом от 27.07.2006 N 152-ФЗ \"О персональных данных\".",
      "Оператор может обрабатывать email, идентификатор Apple ID, имя, возраст, пол, город, район, предпочитаемые районы, виды спорта, спортивный уровень, доступность, фото, видео, сообщения, игровые заявки, сведения об активности, push-токены, технические данные устройства, IP-адрес, user-agent и иные данные, которые Пользователь передает при использовании сервиса.",
      "Цели обработки: создание и поддержка аккаунта, подтверждение email или Apple ID, подбор спортивных партнеров, показ профиля другим Пользователям в рамках функций сервиса, организация переписки и игровых заявок, отправка сервисных уведомлений, безопасность, предотвращение злоупотреблений, поддержка Пользователей, аналитика качества и выполнение требований закона.",
      "Согласие действует до удаления аккаунта, отзыва согласия или достижения целей обработки, если более длительный срок хранения не требуется законом или защитой прав Оператора и Пользователей."
    ]
  },
  {
    title: "9. Согласие на распространение данных в сервисе",
    paragraphs: [
      "Пользователь понимает, что часть данных профиля и игровых заявок может быть показана другим Пользователям для поиска партнеров и согласования игр. К таким данным могут относиться имя, возраст, город, район, виды спорта, уровень, доступность, фото, видео, описание профиля, активные поиски и игровые предложения.",
      "Пользователь самостоятельно не размещает данные, которые не хочет показывать другим Пользователям, и может изменить или удалить часть сведений в профиле, если соответствующая функция доступна."
    ]
  },
  {
    title: "10. Уведомления",
    paragraphs: [
      "Сервис может отправлять коды подтверждения, сообщения о матчах, игровых заявках, чатах, изменениях статуса, безопасности аккаунта и иных событиях, необходимых для работы сервиса.",
      "Рекламные рассылки, если они будут введены, должны направляться только при наличии отдельного согласия Пользователя, когда такое согласие требуется законом."
    ]
  },
  {
    title: "11. Интеллектуальные права",
    paragraphs: [
      "Исключительные права на сервис, интерфейсы, программный код, дизайн, базы данных, товарные обозначения и иные элементы сервиса принадлежат Оператору или его правообладателям.",
      "Размещая Контент, Пользователь подтверждает наличие прав на него и предоставляет Оператору неисключительную безвозмездную лицензию на хранение, обработку, воспроизведение, показ, адаптацию и доведение Контента до сведения других Пользователей в объеме, необходимом для работы сервиса."
    ]
  },
  {
    title: "12. Платные функции",
    paragraphs: [
      "Если в сервисе будут доступны платные функции, подписки или премиальные возможности, их цена, порядок оплаты, срок действия, условия продления и возврата указываются в интерфейсе сервиса, правилах магазина приложений или отдельной оферте.",
      "Ничто в Соглашении не ограничивает права потребителя, которые не могут быть ограничены по законодательству Российской Федерации."
    ]
  },
  {
    title: "13. Ответственность",
    paragraphs: [
      "Сервис предоставляется в состоянии \"как есть\" в пределах, допустимых законом. Оператор стремится поддерживать доступность и корректность функций, но не гарантирует бесперебойную работу, отсутствие ошибок, совместимость с каждым устройством или достижение конкретного спортивного результата.",
      "Оператор не отвечает за действия и бездействие Пользователей, достоверность размещенных ими сведений, качество спортивных площадок, травмы, убытки или споры, возникшие при личных встречах, если иное прямо не предусмотрено законом.",
      "Ограничения ответственности применяются только в той мере, в какой они допустимы императивными нормами законодательства Российской Федерации."
    ]
  },
  {
    title: "14. Изменение соглашения",
    paragraphs: [
      "Оператор вправе изменять Соглашение. Новая редакция размещается в сервисе с указанием версии и даты вступления в силу.",
      "Если изменения существенно влияют на права или обязанности Пользователя, Оператор может запросить повторное согласие при следующем входе, регистрации или использовании значимой функции."
    ]
  },
  {
    title: "15. Удаление аккаунта и отзыв согласия",
    paragraphs: [
      "Пользователь может обратиться к Оператору для удаления аккаунта, уточнения, блокирования или удаления персональных данных, а также для отзыва согласия на обработку персональных данных.",
      "Отзыв согласия может привести к невозможности использовать аккаунт и функции сервиса, для которых обработка данных необходима. Оператор вправе продолжить хранение отдельных сведений, если это требуется законом, бухгалтерским учетом, безопасностью, разрешением споров или защитой прав."
    ]
  },
  {
    title: "16. Применимое право и споры",
    paragraphs: [
      "К Соглашению применяется право Российской Федерации.",
      "До обращения в суд стороны стремятся урегулировать спор путем направления письменной претензии на контактный email Оператора. Срок ответа на претензию - 30 календарных дней, если иной срок не установлен законом.",
      "Подсудность определяется по правилам законодательства Российской Федерации, включая обязательные правила о защите прав потребителей, если они применимы."
    ]
  },
  {
    title: "17. Реквизиты и контакты",
    bullets: LEGAL_OPERATOR_DETAILS
  }
];

const LEGAL_OPERATOR_DETAILS_EN = [
  `Operator: ${LEGAL_OPERATOR.legalName}`,
  LEGAL_OPERATOR.inn
    ? `Taxpayer Identification Number (INN): ${LEGAL_OPERATOR.inn.replace(/^ИНН:\s*/, "")}`
    : "",
  LEGAL_OPERATOR.ogrn,
  LEGAL_OPERATOR.address,
  `Contact email: ${LEGAL_OPERATOR.email}`
].filter(Boolean);

// Keep this document structurally aligned with USER_AGREEMENT_SECTIONS. The
// Russian text remains the governing source; this is its complete English version.
export const USER_AGREEMENT_SECTIONS_EN: UserAgreementSection[] = [
  {
    title: "1. General provisions",
    paragraphs: [
      `These Terms of Use govern the relationship between ${LEGAL_OPERATOR.legalName} (the “Operator”) and the person using the ${LEGAL_OPERATOR.serviceName} service through the website, PWA, iOS application, API, or other service interfaces (the “User”).`,
      "These Terms constitute a public offer within the meaning of Articles 435, 437, and 438 of the Civil Code of the Russian Federation. Registration, signing in to an account, email confirmation, signing in with Apple ID, checking the consent box, or continued use of the service constitutes full and unconditional acceptance of these Terms.",
      "If the User does not agree to these Terms, the User must discontinue registration and must not use service features that require an account."
    ]
  },
  {
    title: "2. Definitions",
    bullets: [
      "Service means the SportSearch software suite for finding sports partners, game requests, chats, notifications, and related features.",
      "Account means the User account created using an email code or Apple ID.",
      "Profile means information provided by the User in the service, including name, age, city, district, sports, skill level, availability, photos, videos, and other data.",
      "Content means texts, messages, photos, videos, reviews, requests, responses, and other materials posted by the User.",
      "Game Request means a game offer or search created by the User to arrange the sport, time, place, and participants."
    ]
  },
  {
    title: "3. Scope of the Terms",
    paragraphs: [
      "The Operator provides the User with the technical ability to create a profile, find sports partners, respond to game requests, communicate through chats, receive service notifications, and use other available features.",
      "The Operator is not an organizer of sporting events, a coach, a medical adviser, an owner of sports facilities, or a party to arrangements between Users unless expressly stated otherwise.",
      "Users independently agree on the place, time, facility fees, meeting rules, and other terms of playing together."
    ]
  },
  {
    title: "4. Registration and account",
    bullets: [
      "Registration is available to persons aged 18 or older. By creating an Account, the User confirms that they are at least 18 years old and have full legal capacity.",
      "The User must provide a valid email address and must not use another person's Apple ID, email, name, photos, or other data.",
      "The User is responsible for securing access to their email, Apple ID, device, and application session.",
      "The Operator may refuse registration or restrict or terminate access if the User violates these Terms, applicable law, third-party rights, or standards of good-faith conduct within the service."
    ]
  },
  {
    title: "5. Profile, search, and meetings",
    bullets: [
      "The User independently selects sports, skill level, district, availability, search radius, and other profile settings.",
      "Recommendation algorithms use profile, activity, geographic, and game-related parameters to select cards, searches, and notifications.",
      "The User understands that sports involve physical exertion and a risk of injury. Before participating in a game, the User independently assesses their health, fitness level, and facility conditions.",
      "The Operator does not guarantee the availability of suitable partners or sports facilities, attendance by other Users, or the quality of meetings."
    ]
  },
  {
    title: "6. Rules of conduct",
    bullets: [
      "The service has zero tolerance for objectionable, offensive, or unlawful Content, as well as for Users who threaten, harass, demean others, or otherwise abuse service features.",
      "Threats, insults, discrimination, harassment, spam, fraud, impersonation, and actions that violate the rights of other Users are prohibited.",
      "Posting unlawful, harmful, pornographic, extremist, defamatory, or rights-infringing Content is prohibited.",
      "Collecting, publishing, or transmitting other Users' personal data without a lawful basis and their consent is prohibited.",
      "Interfering with the service, bypassing restrictions, using bots, bulk extraction, scraping, or unauthorized access is prohibited."
    ]
  },
  {
    title: "7. Moderation and restrictions",
    paragraphs: [
      "The Operator may review reports, hide, remove, or restrict the distribution of Content, and block Accounts and technical identifiers when necessary to comply with the law, protect Users, prevent abuse, or ensure stable operation of the service.",
      "A User may report another User's Profile or materials and block that User using the mechanisms available in the service. After blocking, the blocked User's Content is immediately removed from the blocking User's feed, and the Operator is notified for review.",
      "The Operator reviews reports of objectionable Content and abuse within 24 hours. If a violation is confirmed, the Operator removes or hides the relevant Content and ejects the offending User from the service.",
      "The Operator may temporarily restrict service features during maintenance, in the event of errors or suspected security violations, or as required by law."
    ]
  },
  {
    title: "8. Personal data",
    paragraphs: [
      "By registering for and using the service, the User consents to the Operator's processing of personal data in accordance with Federal Law No. 152-FZ of July 27, 2006, On Personal Data.",
      "The Operator may process the User's email, Apple ID identifier, name, age, gender, city, district, preferred districts, sports, skill level, availability, photos, videos, messages, game requests, activity data, push tokens, device technical data, IP address, user agent, and other data submitted by the User when using the service.",
      "The purposes of processing are creating and maintaining an Account, verifying an email address or Apple ID, matching sports partners, displaying the Profile to other Users within service features, enabling chats and game requests, sending service notifications, maintaining security, preventing abuse, providing User support, analyzing service quality, and complying with legal requirements.",
      "Consent remains valid until the Account is deleted, consent is withdrawn, or the purposes of processing are achieved, unless a longer retention period is required by law or for the protection of the rights of the Operator and Users."
    ]
  },
  {
    title: "9. Consent to data distribution within the service",
    paragraphs: [
      "The User understands that some Profile and game request data may be shown to other Users to find partners and arrange games. Such data may include name, age, city, district, sports, skill level, availability, photos, videos, Profile description, active searches, and game offers.",
      "The User must not post data that they do not want to show to other Users and may change or delete certain Profile information when the relevant feature is available."
    ]
  },
  {
    title: "10. Notifications",
    paragraphs: [
      "The service may send verification codes and notifications about matches, game requests, chats, status changes, Account security, and other events necessary for the operation of the service.",
      "Advertising communications, if introduced, will be sent only with the User's separate consent where such consent is required by law."
    ]
  },
  {
    title: "11. Intellectual property",
    paragraphs: [
      "Exclusive rights to the service, interfaces, software code, design, databases, trademarks, and other service elements belong to the Operator or its rights holders.",
      "By posting Content, the User confirms that they have the rights to it and grants the Operator a non-exclusive, royalty-free license to store, process, reproduce, display, adapt, and make the Content available to other Users to the extent necessary for the operation of the service."
    ]
  },
  {
    title: "12. Paid features",
    paragraphs: [
      "If paid features, subscriptions, or premium capabilities become available in the service, their price, payment procedure, duration, renewal terms, and refund conditions will be stated in the service interface, the application store rules, or a separate offer.",
      "Nothing in these Terms limits consumer rights that cannot be limited under the laws of the Russian Federation."
    ]
  },
  {
    title: "13. Liability",
    paragraphs: [
      "The service is provided “as is” to the extent permitted by law. The Operator strives to maintain service availability and correct operation but does not guarantee uninterrupted operation, absence of errors, compatibility with every device, or achievement of any particular sporting result.",
      "The Operator is not liable for Users' acts or omissions, the accuracy of information they post, the quality of sports facilities, injuries, losses, or disputes arising during in-person meetings unless otherwise expressly required by law.",
      "Limitations of liability apply only to the extent permitted by mandatory provisions of the laws of the Russian Federation."
    ]
  },
  {
    title: "14. Changes to the Terms",
    paragraphs: [
      "The Operator may amend these Terms. A new version will be published in the service together with its version number and effective date.",
      "If changes materially affect the User's rights or obligations, the Operator may request renewed consent upon the next sign-in, registration, or use of a material feature."
    ]
  },
  {
    title: "15. Account deletion and withdrawal of consent",
    paragraphs: [
      "The User may contact the Operator to delete their Account, correct, block, or delete personal data, or withdraw consent to personal-data processing.",
      "Withdrawal of consent may make it impossible to use the Account and service features that require data processing. The Operator may continue to retain certain information if required by law, accounting obligations, security, dispute resolution, or the protection of rights."
    ]
  },
  {
    title: "16. Governing law and disputes",
    paragraphs: [
      "These Terms are governed by the laws of the Russian Federation.",
      "Before commencing court proceedings, the parties will seek to resolve a dispute by sending a written claim to the Operator's contact email. The response period is 30 calendar days unless a different period is established by law.",
      "Jurisdiction is determined under the laws of the Russian Federation, including mandatory consumer-protection rules where applicable."
    ]
  },
  {
    title: "17. Operator details and contacts",
    bullets: LEGAL_OPERATOR_DETAILS_EN
  }
];

export const USER_AGREEMENT_DOCUMENTS: Record<LegalLanguage, UserAgreementDocument> = {
  ru: {
    language: "ru",
    title: USER_AGREEMENT_TITLE,
    description: "Пользовательское соглашение сервиса SportSearch",
    version: USER_AGREEMENT_VERSION,
    effectiveDate: USER_AGREEMENT_EFFECTIVE_DATE,
    backLabel: "Назад к регистрации",
    versionLabel: "Редакция",
    effectiveDateLabel: "Дата вступления в силу",
    operatorLabel: "Оператор",
    sections: USER_AGREEMENT_SECTIONS
  },
  en: {
    language: "en",
    title: "SportSearch Terms of Use",
    description: "Terms of Use for the SportSearch service",
    version: USER_AGREEMENT_VERSION,
    effectiveDate: "August 24, 2026",
    backLabel: "Back to registration",
    versionLabel: "Version",
    effectiveDateLabel: "Effective date",
    operatorLabel: "Operator",
    sections: USER_AGREEMENT_SECTIONS_EN
  }
};

export function resolveLegalLanguage(value: string | string[] | undefined): LegalLanguage {
  return value === "en" ? "en" : "ru";
}

export function getUserAgreementDocument(value: string | string[] | undefined): UserAgreementDocument {
  return USER_AGREEMENT_DOCUMENTS[resolveLegalLanguage(value)];
}
