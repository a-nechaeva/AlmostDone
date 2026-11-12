-- Allergens of ingredients: the gaps left in compound products (sauces, curry
-- pastes, ready dough, dried fruit, wine, stock cubes).
--
-- Links are only added; existing ones stay. Rows are matched by ingredient code and
-- allergen code, and a row whose ingredient is absent is skipped. ingredient_allergens
-- has a trigger that invalidates the server's catalogue cache.

CREATE TEMP TABLE new_ingredient_allergens (
    code text NOT NULL,
    allergen text NOT NULL,
    PRIMARY KEY (code, allergen)
) ON COMMIT DROP;

INSERT INTO new_ingredient_allergens (code, allergen) VALUES
    ('ing_5080f64e5d37ea5c', 'eggs'),  -- Яйцо куриное
    ('ing_9f5aff656efd8171', 'gluten'),  -- Мука
    ('ing_f9488f0bc6429a47', 'milk'),  -- Масло сливочное
    ('ing_69f91741a4c2027f', 'milk'),  -- Молоко
    ('ing_c5a774f804da9082', 'milk'),  -- Масло топлёное
    ('ing_b91626a52dbb2f02', 'milk'),  -- Сметана
    ('ing_ef633f7569b37d4b', 'sulphites'),  -- Изюм
    ('ing_3114ece82c6e01a9', 'milk'),  -- Сливки
    ('ing_806d0f13effa3beb', 'soy'),  -- Соус соевый
    ('ing_806d0f13effa3beb', 'gluten'),  -- Соус соевый
    ('ing_17d4eeeec05e425e', 'crustaceans'),  -- Креветки
    ('ing_c3d66be69bae22f7', 'sulphites'),  -- Вино белое сухое
    ('ing_234a7b19ef28f34c', 'fish'),  -- Рыбный соус
    ('ing_f8f3d2c774368db3', 'nuts'),  -- Грецкий орех
    ('ing_d549d6eee8612558', 'sesame'),  -- Кунжут
    ('ing_5e3d8980c5685bfd', 'mustard'),  -- Горчица
    ('ing_95a89b6820bca228', 'milk'),  -- Йогурт
    ('ing_a01d24c8cf22fdb4', 'milk'),  -- Йогурт густой
    ('ing_c2451537e0a091ea', 'gluten'),  -- Панировочные сухари
    ('ing_fbfbeef2dd1eef71', 'milk'),  -- Сливки 33%
    ('ing_ecbb1c68c19cf5b0', 'nuts'),  -- Миндаль
    ('ing_f52e09ee7d721bae', 'peanuts'),  -- Арахисовая паста
    ('ing_41360252fe44aaf0', 'milk'),  -- Брынза
    ('ing_1501282cfef1c9ab', 'peanuts'),  -- Арахис жареный
    ('ing_966fa72f442283a4', 'gluten'),  -- Белый хлеб
    ('ing_10f40654579eda70', 'nuts'),  -- Кедровые орехи
    ('ing_f76b62d7371964a9', 'celery'),  -- Корень сельдерея
    ('ing_0e0ce360bffc5c76', 'celery'),  -- Сельдерей стеблевой
    ('ing_41e683c6f21c8720', 'peanuts'),  -- Арахис
    ('ing_384d9b040efc72c4', 'sulphites'),  -- Винный уксус
    ('ing_58a686c981ca848e', 'milk'),  -- Кефир
    ('ing_dd786d8ed9d32aff', 'sesame'),  -- Кунжутное масло
    ('ing_f49d3ee4e597f8d9', 'eggs'),  -- Майонез
    ('ing_14e2f4a3b901e6c8', 'sulphites'),  -- Вино красное сухое
    ('ing_1ca7630ef99fedc1', 'gluten'),  -- Вино шаосинское
    ('ing_1ca7630ef99fedc1', 'sulphites'),  -- Вино шаосинское
    ('ing_51ed7c37c730a2b3', 'fish'),  -- Даси
    ('ing_1938963dbc6825a1', 'milk'),  -- Пармезан
    ('ing_0a7d9d11e8664161', 'soy'),  -- Тёмный шоколад
    ('ing_620c157641150703', 'gluten'),  -- Бульонный кубик
    ('ing_620c157641150703', 'soy'),  -- Бульонный кубик
    ('ing_8f8341b4ec2c26d3', 'milk'),  -- Моцарелла
    ('ing_e34efbe35f19b8a9', 'gluten'),  -- Овсяные хлопья
    ('ing_fe48929000e63062', 'gluten'),  -- Перловая крупа
    ('ing_4c851ed4c2ae3163', 'gluten'),  -- Пита
    ('ing_e856c55070fd163b', 'soy'),  -- Соус соевый тёмный
    ('ing_e856c55070fd163b', 'gluten'),  -- Соус соевый тёмный
    ('ing_30b94c6b1df6b7ec', 'milk'),  -- Творог
    ('ing_ff76bee750f4e0f9', 'sulphites'),  -- Уксус винный красный
    ('ing_90f660487ae6557b', 'gluten'),  -- Багет
    ('ing_6124124d0db607e1', 'fish'),  -- Белая рыба
    ('ing_4ae837dc2ffb11ad', 'fish'),  -- Вустерский соус
    ('ing_4ae837dc2ffb11ad', 'gluten'),  -- Вустерский соус
    ('ing_f7fc80979fe84626', 'sulphites'),  -- Курага
    ('ing_e4e8ba6430e3f192', 'gluten'),  -- Лепёшки
    ('ing_ca60b9ac43bee389', 'mustard'),  -- Маринованная горчичная зелень
    ('ing_20156eec00aebb94', 'gluten'),  -- Ржаная мука
    ('ing_95ea2c1a2dc42cd7', 'gluten'),  -- Ржаной хлеб
    ('ing_df3962e6d00b9d59', 'milk'),  -- Сгущённое молоко
    ('ing_5b8f0dec3d533054', 'soy'),  -- Соус соевый светлый
    ('ing_5b8f0dec3d533054', 'gluten'),  -- Соус соевый светлый
    ('ing_23b698d1180bb31d', 'sesame'),  -- Тахини
    ('ing_331854928dfbda9c', 'gluten'),  -- Тесто фило
    ('ing_848f0aeed1309f0d', 'nuts'),  -- Фисташки
    ('ing_35cdf50e01180cc7', 'gluten'),  -- Булгур мелкий
    ('ing_c7be7888b30b637f', 'mustard'),  -- Горчица семена
    ('ing_c8b206eaefb611e3', 'milk'),  -- Грюйер
    ('ing_1df23a2bc45c1a15', 'crustaceans'),  -- Креветочная паста белачан
    ('ing_74e38d82c40f131d', 'gluten'),  -- Мука высокобелковая
    ('ing_b16683d00c63b1e8', 'milk'),  -- Пекорино романо
    ('ing_f4e9ed2d02a9c7b0', 'gluten'),  -- Песочное тесто
    ('ing_f4e9ed2d02a9c7b0', 'eggs'),  -- Песочное тесто
    ('ing_b4f49c2f3aa354c0', 'milk'),  -- Сливки 20%
    ('ing_da1c921d4c950665', 'gluten'),  -- Слоёное тесто
    ('ing_27878fd2d8b3bdd2', 'fish'),  -- Солёная треска
    ('ing_7c7b25a2dac982a2', 'fish'),  -- Тунец консервированный
    ('ing_c0cbec0ef9a935b0', 'gluten'),  -- Хлеб
    ('ing_b05b1912afc7ab3a', 'sulphites'),  -- Чернослив
    ('ing_0c76090704763acb', 'gluten'),  -- Булочки
    ('ing_af7bd038fab33ff1', 'gluten'),  -- Вермишель
    ('ing_5585374d6652e15c', 'sulphites'),  -- Вино красное
    ('ing_1ba376987300aa29', 'gluten'),  -- Доубаньцзян
    ('ing_1ba376987300aa29', 'soy'),  -- Доубаньцзян
    ('ing_9000ce51dc7f7bc7', 'gluten'),  -- Дроблёная пшеница
    ('ing_1637a4705f3d7f57', 'milk'),  -- Дульсе де лече
    ('ing_d37c277ae6a11b80', 'fish'),  -- Карп
    ('ing_88bba507f5bc6a24', 'soy'),  -- Кечап манис
    ('ing_88bba507f5bc6a24', 'gluten'),  -- Кечап манис
    ('ing_593c9ec912f44e53', 'nuts'),  -- Кешью
    ('ing_6e329e080950f78a', 'milk'),  -- Концентрированное молоко
    ('ing_24afceb147f8d94b', 'soy'),  -- Кочхуджан
    ('ing_24afceb147f8d94b', 'gluten'),  -- Кочхуджан
    ('ing_8706d49261d6f72f', 'fish'),  -- Мальдивская рыба
    ('ing_11dc460621f83d59', 'gluten'),  -- Манная крупа
    ('ing_1d82933af60e33cd', 'molluscs'),  -- Мидии
    ('ing_da95cc542c5b00fc', 'crustaceans'),  -- Молотые сушёные креветки
    ('ing_1b5368190e679af5', 'milk'),  -- Мягкий белый сыр
    ('ing_af72b628f3fa2f1d', 'gluten'),  -- Пшеничная лапша
    ('ing_6abe6b72ac6cf2fe', 'molluscs'),  -- Ракушки
    ('ing_e438611a9c0188c9', 'milk'),  -- Свежий белый сыр
    ('ing_3ecf5d1b43c0b82e', 'milk'),  -- Свежий солёный сыр
    ('ing_a50951dec7f5c51a', 'gluten'),  -- Светлое пиво
    ('ing_ce720af62e266b3f', 'milk'),  -- Сметана густая
    ('ing_cf4195f8edc74529', 'milk'),  -- Сухой творог
    ('ing_f3cebdd1d2fd2c8b', 'crustaceans'),  -- Сушёные креветки
    ('ing_0aa6315714461a88', 'milk'),  -- Сыр твёрдый
    ('ing_a823569bd09124c4', 'soy'),  -- Тофу
    ('ing_de71cdc48a8c6825', 'gluten'),  -- Тёмное пиво
    ('ing_636aceda5c60993f', 'sulphites'),  -- Уксус хересный
    ('ing_658f381214e73c12', 'sulphites'),  -- Уксус яблочный
    ('ing_b0ffc9ef7e7a3cf0', 'molluscs'),  -- Устричный соус
    ('ing_0a59629643afbf92', 'milk'),  -- Фета
    ('ing_7cf94eaacaee97f5', 'nuts'),  -- Фундук
    ('ing_94b0966a8a096297', 'milk'),  -- Халуми
    ('ing_66e65b21412cc940', 'gluten'),  -- Цельная пшеница
    ('ing_3dba4063483a66f8', 'gluten'),  -- Чёрствый белый хлеб
    ('ing_bdf1db9b5f817f87', 'gluten'),  -- Чёрствый хлеб
    ('ing_8f54a5b080724517', 'milk'),  -- Адыгейский сыр
    ('ing_ad6eaf502996bae2', 'sulphites'),  -- Алыча сушёная
    ('ing_93344d905e3a6507', 'fish'),  -- Белая рыба для сырого потребления
    ('ing_9f8f52ea79271af6', 'milk'),  -- Белый рассольный сыр
    ('ing_25843a4c22415dee', 'milk'),  -- Болгарский йогурт
    ('ing_7563895ec9dff0ac', 'gluten'),  -- Борщ из отрубей
    ('ing_f37de3ffb21edcab', 'gluten'),  -- Букатини
    ('ing_18ced12062b87f0b', 'gluten'),  -- Булочки для хот-дога
    ('ing_a4466bc12d1f28b0', 'gluten'),  -- Булочки мантоу
    ('ing_f38c5d1ba59fc1f7', 'fish'),  -- Бульон рыбный
    ('ing_7b8803a1a4d95bd3', 'milk'),  -- Вашрен фрибуржуа
    ('ing_a970c972f498dddd', 'fish'),  -- Вяленая рыба
    ('ing_a44c8d3dc2b4e2d0', 'mustard'),  -- Горчица английская
    ('ing_7595b0e77f3e46c9', 'mustard'),  -- Горчица дижонская
    ('ing_a7bb91b82cea1b41', 'mustard'),  -- Горчица средней остроты
    ('ing_ae1e5ff2b568a531', 'mustard'),  -- Горчичный порошок
    ('ing_5fbb19a17a6024b0', 'gluten'),  -- Деревенский хлеб
    ('ing_3ed85f4d02e8a5aa', 'milk'),  -- Джамид
    ('ing_173ff344a6bced92', 'gluten'),  -- Дзавар (пшеничная крупа)
    ('ing_07fc41b1cf16a86a', 'gluten'),  -- Дроблёная пшеница джариш
    ('ing_6e29a1973a3704e8', 'soy'),  -- Жареный тофу
    ('ing_2d0f56367ef6d1bb', 'gluten'),  -- Имбирные пряники
    ('ing_bb16582d90268cf2', 'milk'),  -- Йогурт с чесноком
    ('ing_c49b84a1423eea48', 'milk'),  -- Каймак
    ('ing_e7e0333431aaf6ba', 'fish'),  -- Камабоко
    ('ing_ff455b1a851405a0', 'molluscs'),  -- Каракатица
    ('ing_de95d2c9276c050c', 'fish'),  -- Кацуобуси
    ('ing_92921f33ecd6d266', 'milk'),  -- Кашкавал
    ('ing_342b2cadd629badc', 'gluten'),  -- Кипрская пита
    ('ing_3c98bb627a6cf726', 'fish'),  -- Копчёная рыба
    ('ing_f3ba1c6b38d0f72e', 'crustaceans'),  -- Краб
    ('ing_a1d763ddff83a641', 'crustaceans'),  -- Креветочная паста терази
    ('ing_c787ddbc69ee975a', 'fish'),  -- Крупная белая рыба
    ('ing_f286f6484691efaa', 'gluten'),  -- Кукурузный хлеб
    ('ing_39394d63d69b8cd4', 'milk'),  -- Курут
    ('ing_7e7394f911f56a8a', 'gluten'),  -- Кускус
    ('ing_e736d2cfde73295d', 'gluten'),  -- Лапша для рамена
    ('ing_e8716ac094412cec', 'gluten'),  -- Лепёшка наан
    ('ing_71688ec87941115b', 'gluten'),  -- Лепёшка пиде
    ('ing_ff66960938de8f6d', 'gluten'),  -- Лепёшки сомун
    ('ing_6f95d6b852db3bb6', 'gluten'),  -- Лепёшки таббун
    ('ing_44174578bd47c24b', 'gluten'),  -- Листы для лазаньи
    ('ing_35b7c49a2ba2a6db', 'celery'),  -- Листья сельдерея
    ('ing_e9c8bfefc9255c2f', 'gluten'),  -- Ломоть хлеба
    ('ing_22605083f0246082', 'fish'),  -- Маринованная сельдь
    ('ing_79844ac37df050fc', 'sulphites'),  -- Марсала
    ('ing_96b31f47190e8ad8', 'milk'),  -- Маскарпоне
    ('ing_84bfceb727ee95e0', 'fish'),  -- Мелкая костистая рыба
    ('ing_8fbe8cb2e1e8de33', 'fish'),  -- Мелкая речная рыба
    ('ing_a44e51501488254a', 'gluten'),  -- Мелкие макароны
    ('ing_fee34177b0906d3a', 'molluscs'),  -- Моллюски
    ('ing_064622856e856edb', 'milk'),  -- Молодой солёный сыр
    ('ing_565de69a603ebf4d', 'milk'),  -- Молоко обезжиренное
    ('ing_dd8ef1394214b4b9', 'crustaceans'),  -- Молотые сушёные раки
    ('ing_e07b9b59d2497d90', 'gluten'),  -- Мука кама
    ('ing_26ef01b95836d58c', 'gluten'),  -- Мука обжаренная
    ('ing_a90523acfe8a4f74', 'gluten'),  -- Мука типа 00
    ('ing_e1e2308ca61bb684', 'soy'),  -- Мягкий тофу
    ('ing_c38958520e1fd09a', 'milk'),  -- Овечья брынза
    ('ing_31c5f236dafed43f', 'nuts'),  -- Орехи кемири
    ('ing_333071b1d24de184', 'molluscs'),  -- Осьминог
    ('ing_bcfca224cd1d076b', 'milk'),  -- Панир
    ('ing_6dee3c371763550a', 'gluten'),  -- Панко
    ('ing_2d3c656799fdc865', 'crustaceans'),  -- Паста багоонг
    ('ing_f97d3547abfbf9e3', 'soy'),  -- Паста мисо
    ('ing_9453127deb29344b', 'milk'),  -- Пахта
    ('ing_9207a5941ac2bb21', 'soy'),  -- Плотный тофу
    ('ing_3e391c1893a11a6f', 'fish'),  -- Прахок
    ('ing_99282d294b4989b1', 'gluten'),  -- Пресная лепёшка чурек
    ('ing_87e5f4befbe47a1b', 'gluten'),  -- Ржаная закваска
    ('ing_a0258632411582e8', 'gluten'),  -- Ржаной заквас
    ('ing_02e8df7666998ba9', 'gluten'),  -- Ржаной солод
    ('ing_3441172b4d72b565', 'gluten'),  -- Ржаной хлеб ругбрёд
    ('ing_1da51658bca4e6d1', 'milk'),  -- Рикотта
    ('ing_68c0d27b7fcd6ab5', 'soy'),  -- Ростки сои
    ('ing_6ce3a3b8090ed497', 'gluten'),  -- Савоярди
    ('ing_6ce3a3b8090ed497', 'eggs'),  -- Савоярди
    ('ing_2493063dacb42d6e', 'fish'),  -- Сардины
    ('ing_ea42249c35d7e196', 'milk'),  -- Свежий сыр
    ('ing_831a4225e03807d8', 'sulphites'),  -- Сладкое вино
    ('ing_557dc700883ef5f1', 'milk'),  -- Сливки 30%
    ('ing_3366e852e3e49cde', 'milk'),  -- Сливочный сыр катупири
    ('ing_f22fceb6dd681abb', 'gluten'),  -- Слоёная лепёшка фатир
    ('ing_8264b0edfe7f2115', 'soy'),  -- Соевые бобы
    ('ing_8959fc65a0a4dca7', 'gluten'),  -- Солёные крекеры
    ('ing_80802967bc55743f', 'milk'),  -- Солёный белый сыр
    ('ing_22750c03cd1e32f1', 'milk'),  -- Соус из голубого сыра
    ('ing_69dc1800ade951af', 'soy'),  -- Соус хойсин
    ('ing_69dc1800ade951af', 'gluten'),  -- Соус хойсин
    ('ing_73fabe44ad08c4f9', 'fish'),  -- Соус шито
    ('ing_42a5fc5651847134', 'gluten'),  -- Спагетти
    ('ing_7c45a05d7304a546', 'milk'),  -- Сулугуни
    ('ing_d6b81fdd8cd43fc5', 'milk'),  -- Сухое молоко
    ('ing_abdf96df117362e9', 'gluten'),  -- Сухое печенье
    ('ing_d21472ca1c2f503c', 'fish'),  -- Сушёная рыба
    ('ing_117baad5bb7f657e', 'fish'),  -- Сушёные анчоусы икан билис
    ('ing_9190ebeae43aba73', 'milk'),  -- Сыр для жарки
    ('ing_09e490f20328afe8', 'milk'),  -- Сыр для пастель
    ('ing_907dee82d34c84db', 'milk'),  -- Сыр куахада
    ('ing_d1c1993a49865623', 'milk'),  -- Сырные зёрна чеддер
    ('ing_646a495745b3fbf3', 'milk'),  -- Творог 5–9 %
    ('ing_bce1230be14d6ea8', 'milk'),  -- Творог твёрдый
    ('ing_ffbeb3d2d6588370', 'milk'),  -- Творожный сыр джиза
    ('ing_5a7489c12aa4f080', 'gluten'),  -- Тесто для эмпанадас
    ('ing_70c4afe419650faa', 'gluten'),  -- Тесто катаифи
    ('ing_88863e17e4353b9c', 'fish'),  -- Тиляпия
    ('ing_7cf9f87a547fa4ba', 'gluten'),  -- Тонкая лепёшка
    ('ing_0090b21710c0eba0', 'gluten'),  -- Тонкий лаваш
    ('ing_de024bbc09030cbb', 'milk'),  -- Топлёное масло нитер киббе
    ('ing_3e5b0677719c99f0', 'fish'),  -- Треска
    ('ing_2503548b0a13a2b9', 'fish'),  -- Тунец
    ('ing_2ef2854dde1d3bf7', 'gluten'),  -- Тэнкасу — крошка от темпуры
    ('ing_801caaaf7bf2ee30', 'gluten'),  -- Тёмное бельгийское пиво
    ('ing_6e76ad51d3e2a244', 'gluten'),  -- Тёмное пиво стаут
    ('ing_89aed53d19cc1102', 'gluten'),  -- Уксус солодовый
    ('ing_d78ebc629c6cf9fa', 'soy'),  -- Ферментированные бобы иру
    ('ing_c672c00ff072004d', 'soy'),  -- Ферментированные чёрные бобы
    ('ing_6c649ffcbeca5d78', 'fish'),  -- Филе лосося
    ('ing_a6a680919c59e0cb', 'fish'),  -- Филе лосося с кожей
    ('ing_31193f8756698326', 'fish'),  -- Филе трески
    ('ing_37a59b531263036b', 'fish'),  -- Форель
    ('ing_a233ecc1b7e0c9df', 'gluten'),  -- Фрик (зелёная пшеница)
    ('ing_30a11c0b7b37f5eb', 'sulphites'),  -- Херес
    ('ing_a7d6c01eb3f853d0', 'gluten'),  -- Хлеб с плотным мякишем
    ('ing_50a57673e2e72d91', 'gluten'),  -- Цельнозерновая мука
    ('ing_3bcb551d1dc20b74', 'molluscs'),  -- Чернила каракатицы
    ('ing_afea33f8210fc889', 'lupin'),  -- Чочо (люпин)
    ('ing_aab752b6265a2093', 'gluten'),  -- Яичная лапша
    ('ing_aab752b6265a2093', 'eggs'),  -- Яичная лапша
    ('ing_c4a1003022f208ff', 'eggs')  -- Японский майонез
;

INSERT INTO public.ingredient_allergens (ingredient_id, allergen_id)
SELECT i.id, a.id
FROM new_ingredient_allergens n
JOIN public.ingredients i ON i.code = n.code
JOIN public.allergens a ON a.code = n.allergen
ON CONFLICT DO NOTHING;
