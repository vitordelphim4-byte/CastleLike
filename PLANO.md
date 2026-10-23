# CastleLike — Plano 2 (antes dos monstros)

Base atual: mundo infinito procedural, construção (blocos, peças, telhados, portas, escadas),
escavação, corte de árvores, estoque 3x3, tabela de prioridades estilo RimWorld, aldeões voxel.

Diretrizes: Castle Story é a base; RimWorld para gestão de colônia. Tudo gerado por código (VoxelMesh).
Cada fase termina com jogo rodando + 1 teste em `tests/`.
Perguntas marcadas com **?** serão feitas quando chegarmos na fase.

---

## Fase 1 — Ciclo dia e noite ✅ (feito 2026-10-23)
- Relógio global em `Game` (`time_of_day` 0..1, `day` contador). Duração do dia configurável (padrão ~10 min reais).
- Sol (`DirectionalLight3D`) gira; cor/energia da luz, céu e névoa interpolados por gradiente (amanhecer, dia, pôr do sol, noite azulada).
- Noite escura mas jogável (Castle Story: dá pra ver tudo). À noite a mesma luz vira lua fraca do lado oposto.
- HUD: relógio/dia na barra superior. Velocidade do jogo: pausa, 1x, 2x, 3x (espaço, 1/2/3).
- Padrão adotado: aldeões trabalham direto à noite (Castle Story), sem tochas.
- **?** (pendente) Dormir à noite com camas (RimWorld)? Tochas construíveis? Rever quando houver fome/casas.

## Fase 2 — Novo mundo, salvar e carregar ✅ (feito 2026-10-23)
- Menu principal: Novo jogo (nome + semente opcional), Continuar, Carregar, Sair.
- Menu de pausa (Esc): Continuar, Salvar (F5), Carregar, Menu principal, Sair. Sair/voltar ao menu salva antes.
- "Apagar mundo" = apagar o arquivo de save na lista de carregar (com confirmação).
- Formato: `user://saves/<nome>.save`, `FileAccess.open_compressed` + `store_var` (nativo, sem lib).
  - Mundo salvo como **semente + só as colunas modificadas** (o resto é regenerado igual pela semente).
  - Também: árvores cortadas/restantes, props (portas, escadas, telhados), blueprints, demolições,
    ordens, estoque, aldeões (posição, prioridades, item carregado), hora do dia.
- Autosave a cada 5 minutos reais + salvar manual. Código: `scripts/save_game.gd`, `scripts/menu.gd`.
- Mapa de debug (`run_debug.bat`) não salva.
- Regra a partir daqui: todo sistema novo adiciona seus dados ao save.

## Fase 3 — Recursos em tabela + visual do estoque ✅ (feito 2026-10-23)
- Tabela `Game.RESOURCES` (nome, capacidade por quadrado). Novo recurso = nova linha + modelo em `stockpile.gd`.
- Zonas de estoque desenhadas (botão "+ Estoque", Editar, x), estilo RimWorld. Zona inicial 3x3 na origem.
- Capacidade: 1 tipo por quadrado; 10 madeiras (pirâmide de troncos 4-3-2-1) ou 16 pedras (tijolos em palete).
  Balanço: árvore dá 2/4/6 madeiras, bloco de pedra escavado dá 1.
- Estoque cheio: lenhador não pega árvore; quem carrega espera ("Sem espaço no estoque").
- Remover/encolher zona move os itens para outros quadrados (o que não couber se perde).
- Sem grama alta e sem escavação/construção nos quadrados de estoque.
- Aldeão já carrega tronco/pedra na mão (modelos existentes). Futuro: minério em caixote, comida em cestos.

## Fase 4 — Novos recursos (minérios e comida)
- Minérios como veios no subterrâneo pelo `world_gen` (novos tipos de bloco, textura com pontos coloridos):
  ferro, carvão, ouro (**?** lista final; Castle Story tem ferro, cristal/energia).
- Escavar bloco de minério rende o minério em vez de pedra.
- Comida inicial: arbustos de frutas silvestres no mapa (coleta, como árvores) — dá comida antes da agricultura.
- **?** Comida terá uso? Recomendo fome simples estilo RimWorld (barra de fome, aldeão vai comer no estoque).
  Sem isso comida só acumula.
- **?** Minério precisa de uso (fornalha → barra de ferro → ferramentas/armas)? Ou só guardar por agora?

## Fase 5 — Animações melhores dos aldeões
- Hoje: braços/pernas balançam por seno. Melhorar mantendo animação por código:
  - Andar com balanço de corpo e cabeça; parado respirando / olhando em volta.
  - Ações próprias: machado (cortar), picareta (escavar), martelo (construir), colher (agachar), subir escada.
  - Carregar item com peso (curva diferente para tronco x tijolo).
  - Transições suaves entre poses (interpolar, sem trocar de pose num quadro).
  - Ferramenta aparece na mão conforme o trabalho.
- Organizar poses numa tabela reutilizável pelos animais da Fase 7.
- **?** Algum vídeo/jogo de referência para o estilo de movimento (WC3 peões?).

## Fase 6 — Agricultura
- Ordem nova "Zona de plantio" (mesmo fluxo de área das ordens atuais).
- Trabalho novo "Agricultor" na tabela de prioridades.
- Ciclo: arar → plantar → crescer (estágios visuais voxel, tempo baseado no dia da Fase 1) → colher → comida no estoque.
- Plantas iniciais: trigo e cenoura (**?** lista).
- **?** Estações/inverno afetando plantio, ou cresce sempre?
- **?** Trigo vira pão (moinho/padaria) ou já é comida direto?

## Fase 7 — Animais e caça
- Animais voxel gerados por código: cervo, coelho, javali (**?** lista); javali reage e ataca quando caçado.
- IA simples: vagar em bando, fugir de aldeões, dormir à noite. Aparecem por bioma ao gerar chunks.
- Trabalho novo "Caçador": ordem "Caçar" clicando no animal (ou área). Caçador com arco
  → reaproveitar para arqueiros de defesa depois.
- Animal abatido vira carcaça → levada ao estoque → carne (comida).
- **?** Domesticar/criar animais (galinha, vaca) agora ou depois?

## Fase 8 — Modo de ordem por cliques
- **?** Precisa definir. Opções:
  - Clicar direto numa árvore/rocha/animal para marcá-la (RimWorld), além das áreas.
  - Selecionar aldeão e clicar no alvo para ele fazer só aquilo (prioridade forçada, RimWorld "prioritize").
  - Ambos.
- Pode ser adiantada (é pequena) assim que definido.

## Fase 9 — Ver dentro da terra
- **?** Precisa definir antes de construir. Opções:
  - Corte por camada: escolher altura Y (PageUp/PageDown) e tudo acima some (Castle Story / Dwarf Fortress).
  - Raio-X: terreno fica transparente perto do cursor/aldeões selecionados.
  - Contorno de aldeões vistos através de paredes (silhueta).
  - Uso: só visual, ou também construir/escavar dentro do corte?

---

## Ordem e dependências
1 Dia/noite → 2 Save → 3 Tabela de recursos/estoque → 4 Minérios/comida → 5 Animações → 6 Agricultura → 7 Animais/caça.
8 e 9 independentes: entram quando as perguntas forem respondidas.
Depois: monstros/noite perigosa, soldados, arqueiros, biomas.
