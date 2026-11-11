# Omarchy Wallpaper FX

[🇬🇧 English](README.md)

26 переходов обоев для [Omarchy](https://omarchy.org) на одном своём фрагментном шейдере. Клон стокового
`omarchy.background`: клики и всё остальное как в стоке, новый только переход между обоями.

![Переход](screenshots/transition.webp)

<!-- Demo video: repo-videos/omarchy-wallpaper-fx.mp4 — drag it here when editing this file on GitHub -->

`slant` (сток), `fade`, `wipe`, `wave`, `grow`, `outer`, `diamond`, `clock`, `blinds`, `doors`, `mosaic`,
`dissolve`, `pixelize`, `ripple`, `swirl`, `crosszoom`, `slide`, `zoom`, `glitch`, `burn`, `waterdrop`,
`hexagon`, `contagion`, `outline`, `random`, `none`. Свои реализации по идеям swww и gl-transitions.

### Переходы-сцены: `contagion` и `outline`

Два неторопливых эффекта (`durationScene`, по умолчанию 1,9 с) по мотивам переходов
[diegoMalagrida/pocket-dots](https://github.com/diegoMalagrida/pocket-dots). Идея — оттуда, код написан заново.

- **contagion**: колонии пикселей появляются в случайных местах и прогрызают старые обои по рваному
  фронту. Только что перевёрнутая клетка вспыхивает самым ярким цветом новой темы, вдоль фронта идёт
  тонкое свечение, изредка впереди проскакивает искра. Полностью процедурный: ни карт, ни Python.
- **outline**: линия рисуется всегда. Сцена отступает, тонкая линия рисует контур персонажа двумя перьями
  от верхней точки: светлая на тёмных местах картинки, тёмная на светлых. Персонаж заливается от линии, потом
  из него вырастает остальной мир. Персонажа один раз на обои вырезает
  [BiRefNet](https://github.com/ZhengPeng7/BiRefNet) (onnxruntime). Пока обои не вырезаны или на них нет явного
  персонажа, линия идёт по краям самой картинки (Canny, строится меньше чем за секунду), и мир растёт из этих линий.

```sh
scripts/wallpaper-fx-outline install   # venv в ~/.local/share/wallpaper-fx + BiRefNet-lite (~220 МБ)
scripts/wallpaper-fx-outline warm      # поставить обои текущей темы в очередь на вырезку
scripts/wallpaper-fx-outline status    # устройство, очередь, воркер, кэш
```

`map` (его вызывает плагин при каждой смене) отвечает сразу: карта персонажа, если есть, иначе карта линий, а
обои встают в очередь на вырезку. Очередь разбирает **один** фоновый воркер на всю систему (flock), под `nice 19`
и `ionice idle`; модель он грузит один раз. Устройство — Intel **NPU**, потом **GPU**, потом CPU (2 потока), что
первым заработает. Для NPU и GPU нужно `sudo pacman -S intel-npu-driver intel-compute-runtime level-zero-loader`.
На CPU вырезка занимает около 10 с, а пик памяти — около 6 ГБ: вход модели фиксированный, 1024².

## Установка

```sh
omarchy plugin add https://github.com/KamradSmeshnyavy/omarchy-wallpaper-fx --enable
omarchy restart shell
echo '{"type": "grow", "duration": 1200, "easing": "InOutCubic", "origin": "cursor"}' \
  > ~/.config/omarchy/wallpaper-transition.json
```

Обои меняются как обычно (`omarchy-theme-bg-next`, переключатель обоев, смена темы). Проиграть текущий
эффект ещё раз:

```sh
omarchy-shell background replay
```

Вернуть стоковый фон: `omarchy plugin enable omarchy.background`.


## Требования

Omarchy 4 (Quattro) с его оболочкой. Проверено на Omarchy 4.0.6 и Quickshell 0.3.2.

- Ничего, кроме Omarchy: переходы — один GLSL-шейдер в Quickshell.
- Только для `outline`: `opencv` и `numpy` для карт линий (системный python или venv); venv вырезки — по желанию.

## Удаление

```sh
omarchy plugin enable omarchy.background      # сначала вернуть стоковый
omarchy plugin remove kamradsmeshnyavy.background
omarchy restart shell
```

Настройки остаются в `~/.config/omarchy/wallpaper-transition.json` — удалите их вручную, если не нужны.

## Настройки — `~/.config/omarchy/wallpaper-transition.json`

Читается на лету.

| Ключ | Умолч. | |
|---|---|---|
| `type` | `slant` | эффект |
| `duration` | `420` | мс |
| `easing` | `InOutCubic` | кривая Qt: InOutQuad, OutExpo, OutBack, OutBounce, Linear, … |
| `angle` | `0` | градусы для wipe / wave / slide |
| `origin` | `center` | откуда круг и капля: center / cursor / random |
| `softness` | `0.02` | ширина мягкого края |
| `durationScene` | `1900` | мс, для contagion / outline (они всегда идут линейно, кривые — в шейдере) |
| `cell` | `6` | px, размер клеток contagion / outline |
| `frontGlow` | `0.9` | 0..1, вспышки и свечение фронта contagion |
| `lineWidth` | `1.5` | px, линия outline |
| `outlineWait` | `3000` | мс ожидания карты, потом contagion (обычно меньше секунды) |

## Правка шейдера

Все эффекты — в `shaders/transition.frag` (номер — `mode`), подаёт его `TransitionEffect.qml`. После правки
пересобрать скомпилированный шейдер (в репо лежат оба файла):

```sh
/usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -O \
  -o shaders/transition.frag.qsb shaders/transition.frag
```

Правки стокового `Background.qml` помечены `// fx:`.

В [моих dotfiles](https://github.com/KamradSmeshnyavy/dotfiles) эффект и настройки выбираются в оверлее
Customizer (Wallpaper FX, `p` — проиграть).

## Вместе с Customizer

[omarchy-customizer](https://github.com/KamradSmeshnyavy/omarchy-customizer) — один оверлей (Super+Shift+T) с живым предпросмотром для настроек этого
плагина и всего остального оформления: темы, обои, анимации Hyprland, прозрачность, блюр, шейдеры экрана.
Поставьте его рядом с этим плагином (остальные компаньоны он найдёт сам):

```sh
omarchy plugin add https://github.com/KamradSmeshnyavy/omarchy-customizer --enable
```

## Лицензия

MIT. Основано на `omarchy.background` из [Omarchy](https://github.com/basecamp/omarchy) (MIT, © David
Heinemeier Hansson). Переходы `contagion` / `outline` — по мотивам
[pocket-dots](https://github.com/diegoMalagrida/pocket-dots) (GPL-3.0); код оттуда не брался.
