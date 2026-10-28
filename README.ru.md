# Omarchy Wallpaper FX

[🇬🇧 English](README.md)

24 перехода обоев для [Omarchy](https://omarchy.org) на одном своём фрагментном шейдере. Клон стокового
`omarchy.background`: клики и всё остальное как в стоке, новый только переход между обоями.

![Переход](screenshots/transition.webp)

`slant` (сток), `fade`, `wipe`, `wave`, `grow`, `outer`, `diamond`, `clock`, `blinds`, `doors`, `mosaic`,
`dissolve`, `pixelize`, `ripple`, `swirl`, `crosszoom`, `slide`, `zoom`, `glitch`, `burn`, `waterdrop`,
`hexagon`, `random`, `none`. Свои реализации по идеям swww и gl-transitions.

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

Проверено на Omarchy 4.0.6 и Quickshell 0.3.2.

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
Одна команда ставит его и предлагает этот плагин и остальные:

```sh
curl -fsSL https://raw.githubusercontent.com/KamradSmeshnyavy/omarchy-customizer/main/install.sh | bash
```

## Лицензия

MIT. Основано на `omarchy.background` из [Omarchy](https://github.com/basecamp/omarchy) (MIT, © David
Heinemeier Hansson).
