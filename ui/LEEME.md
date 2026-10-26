# Interfaces (menús, pausa, ajustes y guardado)

Todo el estilo (metal cepillado + neón azul) sale de `ui/estilo.gd` (`const E := preload("res://ui/estilo.gd")`):
`E.fondo()`, `E.boton()`, `E.panel()`, `E.titulo()`, `E.barra()`, `E.deslizador()`, `E.confirmar()`…
El fondo es el shader `ui/fondo_metal.gdshader`.

| Pantalla | Escena / script | Qué hace |
|---|---|---|
| Menú principal | `Scenes/UI.tscn` + `Scenes/ui.gd` | Continuar (solo si hay partida), Nueva partida, Ajustes, Salir. Es la escena principal del proyecto. |
| Selector de clase | `Scenes/BuildSelector.tscn` + `Scenes/build_selector.gd` | Lista de clases, personaje 3D con su armadura y armas sobre un pedestal (arrástralo para girarlo), atributos. ↑/↓, Enter, Esc. |
| Ajustes | `Scenes/Settings.tscn` + `Scenes/settings.gd` | Usa `ui/panel_ajustes.gd` (el mismo panel del menú de pausa). |
| Pausa | `ui/menu_pausa.gd` (lo crea el jugador) | Esc. Continuar, Estado del personaje, Controles, Ajustes, Volver a la hoguera, Menú principal, Salir. Pausa el árbol. |

## Autoloads (project.godot)
- **Ajustes** (`ui/ajustes.gd`): volumen general, música (bus "Musica"), brillo, campo de visión, pantalla completa, VSync, FPS y sensibilidad. Se guardan en `user://ajustes.cfg`.
- **Partida** (`ui/partida.gd`): guardado en `user://partida.json`. **Solo se guarda al descansar en una hoguera** (`VidaDelCampus._on_interact`). Guarda clase, hoguera, hogueras encendidas, jefes vencidos, piezas de llave, tazas, armaduras de resistencia y tiempo jugado. "Continuar" carga `main.tscn` y `Partida.aplicar()` lo restaura (los jefes vencidos usan `restore_won()` de cada pelea).

`Scenes/SettingsMenu.tscn` / `settings_menu.gd` es un duplicado viejo que no usa nada.
