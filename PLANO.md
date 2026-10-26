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
### 4a — Ferro + produção ✅ (feito 2026-10-23)
- Minério de ferro em veios na pedra (até 10 blocos abaixo da superfície, à vista em montanhas).
- Produção estilo RimWorld simplificado: estações com receitas (Desligado / Repetir sempre / Fazer até ter N),
  trabalho novo "Artesão". Carvoaria (madeira → carvão) e Fornalha (minério + carvão → barra de ferro).
- Árvore de produção documentada em `docs/crafting.md` (fonte dos números: `scripts/crafting.gd`).
### 4b — Comida + fome ✅ (feito 2026-10-23)
- Arbustos de frutas silvestres (florestas e campos); ordem "Colher frutas", trabalho "Coletor". Arbusto fica,
  frutas voltam em 1 dia. Colônia começa com 20 frutas.
- Fome simples: barra esvazia em 1 dia; < 30% vai comer no estoque; sem comida = metade da velocidade.
  Sem morte por fome por enquanto. Barra de fome no card de cada aldeão.
- **?** Morte/doença por fome? Comer em mesa/refeitório (RimWorld)? Rever com casas e camas.
- **?** Uso da barra de ferro: ferramentas (trabalho mais rápido), armas, peças de metal? Outros minérios depois.

## Fase 5 — Animações melhores dos aldeões ✅ (feito 2026-10-24)
- Corpo articulado (tronco + cabeça + braços num pivô do quadril): balança, inclina, torce.
- Toda pose é um alvo; cada parte desliza até ele (transições suaves).
- Andar com balanço; parado respira e olha em volta; com fome anda de cabeça baixa.
- Machado: golpe lateral com torção. Picareta/demolir: golpe por cima da cabeça. Martelo (construir/artesão):
  batidas rápidas com uma mão. Colher: agachado, mãos alternando. Comer: mão à boca. Escada: olha pra cima.
- Lascas voam no impacto (madeira, terra/pedra na cor do bloco, poeira na construção).
- Carga: tronco no ombro; pedra/minério/ferro com os dois braços e passo pesado; carvão/frutas numa mão.
- Tabela de poses para animais: fica para a Fase 7 (quadrúpedes têm outro corpo).

## Fase 6 — Agricultura ✅ (feito 2026-10-24)
- Feito: zona "Plantação" desenhada (Editar / x, botão troca cultura), trabalho "Agricultor" (colhe antes de
  plantar), sem sementes, cresce sempre. Trigo (1,5 dia, 6/quadrado, comida fraca) e cenoura (1 dia, 4, 25%).
  Plantar vira a grama em terra arada; 4 estágios visuais. Aldeão come qualquer comida do estoque.
- Padrões adotados sem resposta: trigo + cenoura; sem estações; trigo cru comestível (pão depois).
### Plano original
- Ordem nova "Zona de plantio" (mesmo fluxo de área das ordens atuais).
- Trabalho novo "Agricultor" na tabela de prioridades.
- Ciclo: arar → plantar → crescer (estágios visuais voxel, tempo baseado no dia da Fase 1) → colher → comida no estoque.
- Plantas iniciais: trigo e cenoura (**?** lista).
- **?** Estações/inverno afetando plantio, ou cresce sempre?
- **?** Trigo vira pão (moinho/padaria) ou já é comida direto?

## Fase 7 — Animais e caça ✅ (feito 2026-10-24)
- Feito: coelho, cervo, javali (voxel, pernas animadas, pastam, passeiam, fogem). Bandos surgem perto da colônia
  (máx. 14 vivos). Ordem "Caçar" (área) + trabalho "Caçador": arco (alcance 10, 75%), flechas visíveis,
  carcaça → "limpar" → carne crua (comida 15%). Javali ferido persegue e assusta (aldeões ainda sem vida).
- Padrões adotados sem resposta: coelho/cervo/javali; domesticação depois.
- Futuro: vida/ferimentos dos aldeões (junto com monstros e soldados), domesticar galinha/vaca.
### Plano original
- Animais voxel gerados por código: cervo, coelho, javali (**?** lista); javali reage e ataca quando caçado.
- IA simples: vagar em bando, fugir de aldeões, dormir à noite. Aparecem por bioma ao gerar chunks.
- Trabalho novo "Caçador": ordem "Caçar" clicando no animal (ou área). Caçador com arco
  → reaproveitar para arqueiros de defesa depois.
- Animal abatido vira carcaça → levada ao estoque → carne (comida).
- **?** Domesticar/criar animais (galinha, vaca) agora ou depois?

## Fase 8 — Modo de ordem por cliques ✅ (feito 2026-10-24)
- Ordem direta: aldeões selecionados + botão direito no alvo = fazem aquilo agora, mesmo com o trabalho
  desligado (▶ no card), depois voltam à rotina. Árvore→cortar, arbusto→colher, animal→caçar (e limpar),
  carcaça→limpar, plantação madura→colher, bloco de pedra/minério→escavar; chão→andar.
  Se estiver carregando algo, primeiro leva ao estoque e depois cumpre a ordem.
- Ferramenta Caçar: clique num animal marca/desmarca só ele (seta vermelha), caçado onde estiver.
- Cortar/colher/escavar com um clique = área de 1 quadrado (já funcionava).
### Plano original
- **?** Precisa definir. Opções:
  - Clicar direto numa árvore/rocha/animal para marcá-la (RimWorld), além das áreas.
  - Selecionar aldeão e clicar no alvo para ele fazer só aquilo (prioridade forçada, RimWorld "prioritize").
  - Ambos.
- Pode ser adiantada (é pequena) assim que definido.

## Fase 9 — Ver dentro da terra ✅ (feito 2026-10-24, barra lateral em 2026-10-25)
- Corte por camada, 1 bloco por vez: barra vertical "Altura" no canto superior direito (arrastar, clicar
  ou rolar), ou PageDown/PageUp (Shift = 5 camadas); Home ou o topo da barra mostra tudo. A barra cobre
  40 camadas abaixo e 24 acima do chão natural sob a câmera e mostra a distância até ele (+3, Chão, -5).
  Substituiu o modo "andares de 4 em 4" (testado e descartado: camada a camada é mais flexível).
- Clicar num aldeão (no mundo ou no card da barra do topo) leva o corte ao andar dele: o corpo aparece,
  tudo acima da cabeça some (corte = pés + 2). Ao ar livre sem corte ligado, nada muda.
- Acima do corte nada é desenhado nem clicável (árvores, peças, aldeões, animais, itens do estoque e
  plantas somem inteiros). O plano do corte ganha uma "tampa" mais escura com o tipo real de cada bloco
  (dá para ver minério). Dentro da terra, faces de trás aparecem como rocha escura.
- Raio-X: V liga/desliga um furo no terreno em volta do cursor (6 blocos além da superfície).
  Aldeões selecionados escondidos atrás de terreno ganham o furo sozinhos.
- Silhueta: aldeão atrás de parede/terra aparece como contorno na cor dele.
- Escavar dentro do corte: a área de escavação começa na camada logo abaixo do corte (dá para marcar
  túnel dentro de morro). Escavação agora aceita bloco exposto pelo lado, não só por cima → túneis.
- Construir dentro do corte: o cursor só aponta para blocos visíveis, então dá para construir no chão
  de cavernas/túneis abertos.
- `+`/`-` e roda continuam ajustando altura de construção / profundidade (PageUp/PageDown saíram de lá).
- Fica para depois: cavernas geradas no mundo (otimização da geração), escurecer cavernas sem luz.
### Plano original
- Opções:
  - Corte por camada: escolher altura Y (PageUp/PageDown) e tudo acima some (Castle Story / Dwarf Fortress).
  - Raio-X: terreno fica transparente perto do cursor/aldeões selecionados.
  - Contorno de aldeões vistos através de paredes (silhueta).
  - Uso: só visual, ou também construir/escavar dentro do corte?

## Fase 10 — Cavernas estilo Minecraft
Base: Minecraft 1.18+, onde as cavernas saem de ruído 3D (cada bloco decide sozinho se é ar). Combina
com o nosso gerador, que é uma função pura de (seed, x, z): qualquer coluna sai igual, em qualquer ordem.
Os "vermes" antigos do Minecraft (túneis que atravessam colunas) exigiriam olhar as colunas vizinhas.
Ficam de fora.

Ponto de partida, medido com `bench_worldgen` em 2026-10-25:
- Geração: 1,5 ms por coluna. Navegação: +13 ms. Malhas: +30 ms.
- Profundidade: os planaltos ficam em y ≈ 20–30, então há só ~20 blocos de pedra embaixo da colônia.
  É raso demais para cavernas.

### 10a — Mundo mais fundo ✅ (feito 2026-10-25)
- Terreno +64 blocos (`WorldGen.DEPTH`), `World.SY` 128 → 192, mar em y 82. Mesma paisagem de antes, só
  mais alta.
- Camadas, de baixo para cima: **leito** (y 0, irregular até y 2; não dá para cavar) → **pedra profunda**
  (abaixo de y ~32, borda irregular; mais lenta de cavar, dá pedra) → pedra → solo do bioma.
- Veios de minério estilo Minecraft (caminhadas aleatórias dentro da coluna): **carvão mineral** até
  40 blocos abaixo da superfície (dá o mesmo carvão da carvoaria); ferro em qualquer profundidade,
  com veios dobrados na pedra profunda. As pintas de ferro da superfície continuam. Por coluna: ~46
  carvão, ~118 ferro.
- Saves antigos (versão < 3) sobem 64 blocos ao carregar (posições sobem, direções não), e as colunas
  salvas ganham o subsolo novo do gerador por baixo.
- A câmera acompanha o chão visível sob o corte. A barra "Altura" alcança 80 camadas abaixo (até o leito).
- Medido (bench_worldgen): geração 2,3 ms por coluna (era 1,5), explorar ~48 ms por coluna (era 36–41),
  144 KB por coluna. Para segurar o custo, a geração monta camadas inteiras de pedra de uma vez, e a
  navegação pula seções 100% sólidas. A 10g deve trazer explorar para ≤ 45.
- Teste: `test_deep.gd` (camadas, minério, migração de save).

### 10b — Cavernas "espaguete" (túneis) ✅ (feito 2026-10-25)
- Túneis sinuosos: ar onde dois ruídos 3D (`cave_a`, `cave_b`) ficam os dois perto de zero
  (`CAVE_WIDTH`). Ficam pelo menos `CAVE_ROOF` (4) blocos abaixo da superfície, e nunca cortam leito
  nem água. O minério das paredes aparece, porque os veios entram antes.
- Ocupam ~4,7% do subsolo (seed 1000). O ruído vem em lote, uma fatia 16x16 por camada
  (`get_image_3d`, em C++), e não bloco a bloco no GDScript.
- Visualizador (`run_worldgen_debug.bat`), tecla 8, "Corte vertical": blocos vistos de lado ao longo
  de x, com cavernas em preto, ferro em laranja e carvão em roxo.
- Custo: geração 5,4 ms por coluna (era 2,3). Montar as malhas de todas as cavernas sairia caro:
  30 → 73 ms por coluna, 595 KB por coluna, e o FPS caía de 55 para 44. Por isso:
  - as malhas são montadas seção a seção dentro do orçamento por quadro (sem engasgo), primeiro a
    superfície de todas as colunas;
  - as seções "profundas" (inteiras abaixo do chão natural menos o teto dos túneis) só são montadas e
    desenhadas quando podem aparecer: com o corte ligado, com o raio-X do cursor, ou numa coluna onde
    alguém já cavou até elas. Com tudo normal, o FPS fica igual ao de antes (~55, 18 ms por quadro);
  - enquanto a caverna sob o corte ainda não foi montada, a tampa pinta o buraco de escuro, em vez de
    mostrar o céu;
  - o sombreamento dos cantos (AO) lê o array direto (86 → 73 ms).
  **Pendente na 10g**: montar malhas em threads (com o corte ligado, as cavernas distantes levam alguns
  segundos para aparecer).
- Teste: `test_caves.gd` (3–8% de ar, teto de 4 blocos, mesmo resultado em qualquer ordem e seed).

### 10c — Cavernas "queijo" (salões) ✅ (feito 2026-10-25)
- Salões: ar onde um ruído 3D de baixa frequência (`cave_hall`, FBM com 2 oitavas) passa de um limite.
  O limite cai com a profundidade (`HALL_HIGH` 0,62 no nível do mar → `HALL_DEEP` 0,30 no fundo),
  então os salões ficam grandes e comuns na pedra profunda. O que sobra sólido dentro deles forma os
  pilares. Ficam a pelo menos `HALL_ROOF` (12) blocos da superfície. Saem no mesmo laço dos túneis,
  com o ruído em lote.
- Medido: 9–12% do subsolo vira caverna (túneis ~5% + salões), com salões de 20–40 blocos de largura.
  Em 3 seeds, perto do início, um aldeão anda 47–78 blocos pelas cavernas profundas (navegação).
- Custo: geração 8 ms por coluna (era 5,4). As malhas seguem a regra da 10b (só montadas quando
  podem aparecer).
- Ao ligar o corte, enquanto a vizinhança ainda está sendo montada, aparecem faixas de céu nas
  bordas de salões grandes. Passa sozinho; a 10g (threads) encurta essa espera.
- Teste: `test_caves.gd` (5–15% de ar e caminhada de 16+ blocos em salões de 3 seeds).

### 10d — Entradas e ravinas ✅ (feito 2026-10-26)
- Bocas de caverna: onde um ruído 2D raro (`entrance`) passa de `ENTRANCE_MASK`, o teto de 4 blocos dos
  túneis some, e os túneis que sobem rompem a superfície (16–24% das colunas têm alguma boca).
- Ravinas: fendas de ~4–6 blocos ao longo da linha zero de um ruído (como os rios), onde uma máscara
  rara está alta. Descem até 55 blocos e ficam mais finas no fundo.
- Nada de boca ou ravina a menos de `OPEN_CLEAR` (32 blocos) do início, nem em água ou praia.
  Árvores e arbustos não nascem em pontos escavados.
- Visibilidade: a coluna com abertura (e as 8 vizinhas) mostra as cavernas até a profundidade da
  abertura (`open_depth`: a ravina até o fundo, a boca até 24 blocos). Seções profundas só são
  montadas quando vão aparecer.
- Plano escuro abaixo do leito seguindo a câmera: qualquer buraco para uma parte ainda não montada
  mostra escuro, não céu (streaming, corte, bocas).
- Testes: `test_caves.gd`. Em 3 seeds há caminho a pé da superfície até uma caverna 8+ blocos abaixo,
  por uma boca, e nada aberto dentro da área inicial. `test_deep` usa a altura natural (as ravinas
  rebaixam colunas).
- Pendente: `test_commands` falha às vezes quando todos os testes rodam juntos ("dig command
  accepted": a pedra é recusada). Passa sozinho. Investigar.

### 10e — Água estilo Minecraft
Decidido em 2026-10-26:
- Lava fica para a fase de perigo.
- Aldeões andam devagar em água rasa (1 bloco) e evitam água funda.
- **Sem** fonte infinita.
- Rios com correnteza.
- Colocar e tirar água só pelo debug por enquanto (balde depois).

Regras (Minecraft, menos a fonte infinita):
- **Fonte** (nível 8) e **corrente** (níveis 7..1).
- A água cai primeiro. Ao cair, vira coluna "caindo", com nível cheio.
- Sem ter para onde cair, espalha para os lados perdendo 1 nível por bloco, até 7 blocos da fonte.
  Prefere os lados que levam a um buraco a até 4 blocos (ela "procura" a descida).
- Corrente sem fonte alimentando recua e some.
- Atualiza a cada 0,25 s, como o Minecraft (5 ticks). Só simula as células ativas (que mudaram ou
  têm vizinho que mudou), dentro de um orçamento por quadro. Água parada não custa nada.

#### 10e1 — Motor de água + laboratório de testes ✅ (feito 2026-10-26)
- Blocos novos `FLOW_1..FLOW_7` (corrente) e `FALLING` (caindo). `WATER` é a fonte. Helpers
  `World.is_water()` e `water_level()`.
- `scripts/fluids.gd` (nó `Fluids`, filho do World): fila de células ativas, um passo a cada 0,25 s de
  jogo (segue a velocidade do jogo). Só a água se atualiza; células secas só recebem água empurrada,
  e é isso que deixa ela escolher a direção da descida. Até 4000 células por passo.
- Cavar ou construir acorda a água vizinha (`set_blocks` → `fluids.wake`). Mudanças de água só
  refazem a malha da água da seção (a água não muda faces nem o sombreamento do terreno), em fila,
  com 3 ms por quadro. Navegação atualizada por célula.
- Superfície por nível já nesta etapa: fonte a 0,88 do bloco, corrente de ~0,2 a ~0,87.
- Laboratório no mapa de debug (sul do estoque) e linha "Água" no painel F1: Ir ao lab, Cascata,
  Quebrar tanque, Escada, Cavar ao lado do lago, Fonte no chão, Fonte aqui (câmera), Tirar fonte
  aqui, Água x10, Reiniciar lab. O status mostra quantas células de água estão ativas.
- Teste: `test_water.gd` (espalha 7, seca sem fonte, cai antes de espalhar, procura a descida, não
  cria fonte entre duas, cavar ao lado de um lago inunda).
- Fica para a 10e2: grama aparecendo através da água rasa e transição entre níveis vizinhos.

#### 10e2 — Visual da água corrente ✅ (feito 2026-10-26)
- Superfície contínua: a altura de cada canto é a média das células de água que o compartilham, e
  vai ao topo se alguma delas tiver água em cima (cascata). Vizinhos dividem cantos, então não há
  degrau nem fresta. Faces só voltadas para o ar, e o topo inclinado tem normal real para a luz.
- Correnteza: `_water_flow` calcula a direção (para a água mais baixa e para a queda na borda) e
  manda no vértice. O shader desenha listras correndo nessa direção, e as cascatas ganham listras
  descendo. Lago e mar parados ficam lisos.
- Tufos de grama somem quando a água cobre a grama e voltam quando ela seca (seção inteira refeita,
  em fila).
- Desempenho: água contada por seção (`wet`, como `opaque`), e seções secas pulam a malha de água.
  Atalho para superfície de lago/mar. `is_water` escrito por extenso nos laços quentes, porque a
  chamada de função custava ~25 ms por coluna. Malhas 75 ms e explorar 90 ms por coluna, como antes
  da água.

#### 10e3 — Aldeões e água ✅ (feito 2026-10-26)
- `World.wadeable(p)`: água nos pés, cabeça no ar, chão embaixo. Entra na navegação com peso
  `WADE_COST` (3) no A*, então o caminho contorna quando o desvio é curto. Água de 2+ blocos fica
  fora da navegação. `walkable` continua sendo chão seco: estoques, plantações e animais novos não
  nascem na água.
- Aldeão com os pés na água anda na metade da velocidade.
- Em água funda ou sem chão embaixo, o aldeão flutua até a superfície e nada até o ponto mais próximo
  onde dá para ficar (`World.nearest_footing`).
- Inundação: cada célula de água que muda atualiza a navegação em volta (já vinha da 10e1).
- Teste: `test_water.gd` (água rasa na navegação com peso, funda fora, aldeão sai da água funda
  em ~1 s).
- Animais andam na água rasa na velocidade normal (ponytail: mais lento quando importar).

#### 10e4 — Rios com correnteza
- Refazer os rios: nascem nas serras e descem em degraus até lagos e mar, com água corrente no
  canal e fontes na nascente.
- São gerados já em equilíbrio, então não custam simulação até alguém mexer neles.
- **?** Largura e frequência dos rios novos.

#### 10e5 — Lagos subterrâneos (aquíferos)
- Bolsões de água parada em cavernas e salões, com nível próprio por região, como os aquíferos do
  Minecraft.
- Cavar até eles inunda o túnel (usa a 10e1).

### 10f — Escuridão e tochas
- Luz do céu propagada por blocos, como no Minecraft: cavernas escuras, entrada clareando.
  Ela fica gravada na malha junto com a oclusão de ambiente, sem luz em tempo real (barato).
- Tocha (peça nova de construção, custa madeira + carvão): ilumina um raio de blocos.
- Base para monstros nascerem no escuro (fase de monstros).
- Teste: um bloco de caverna fechada fica escuro, e um bloco ao lado de uma tocha fica claro.

### 10g — Desempenho
- Ruído 3D em lote (`Noise.get_image_3d` em C++) em vez de bloco a bloco no GDScript.
- Pular blocos onde caverna é impossível (perto do leito, acima da superfície).
- Gerar colunas numa thread (WorkerThreadPool) para não travar ao explorar.
- Navegação dentro de cavernas só quando alguém vai até lá, ou quando o jogador cava até ela.
- Metas (bench_worldgen): geração ≤ 5 ms por coluna. Explorar ≤ 45 ms por coluna (hoje 36).
  Memória ≤ 1,5× a atual.
- Pode ir sendo feita junto com 10b e 10c, se os números estourarem.

### 10h — Biomas de caverna (futuro)
- Caverna exuberante (musgo, plantas: comida no subsolo), estalactites, "deep dark".

---

## Ordem e dependências
1 Dia/noite → 2 Save → 3 Tabela de recursos/estoque → 4 Minérios/comida → 5 Animações → 6 Agricultura → 7 Animais/caça.
8 e 9 independentes: entram quando as perguntas forem respondidas.
10 (cavernas): 10a primeiro (tudo depende da profundidade); 10b → 10c → 10d em ordem; 10e e 10f
independentes depois de 10c; 10g acompanha 10b/10c se os números estourarem.
Depois: monstros/noite perigosa, soldados, arqueiros, biomas.

## Mapa de debug (`run_debug.bat`)
- Plano infinito, recursos infinitos (liga/desliga no painel), casas sem telhado (testes de telhado).
- Área de testes a leste/sul do estoque: Carvoaria + Fornalha prontas, faixa de minério de ferro e de pedra,
  arbustos dos 3 tamanhos, árvores (carvalho e pinheiro, 3 tamanhos), plantação de trigo e de cenoura em
  estágios variados, 2º estoque com um pouco de cada recurso, coelho/cervo/javali.
- Painel de debug (F1): tempo (+1h, +6h, +1 dia, meio-dia, meia-noite, 10x), fome (liga/desliga, com fome,
  famintos, alimentar), recursos (infinito, +10 de tudo, esvaziar), plantas (amadurecer, frutas voltam),
  animais (criar coelho/cervo/javali perto da câmera, matar o mais próximo).
- Morro de testes da Fase 9 a oeste (x -40..-25): pedra com veios de ferro, terra e grama por cima,
  túnel aberto (2 de altura) pelo lado leste até uma câmara, e uma caverna fechada com paredes de minério
  mais acima. Painel, linha "Visão": Ir ao morro, Aldeão na câmara (seleciona: contorno + raio-X automático),
  Corte: túnel, Corte: caverna, Sem corte, Cavar túnel (corte + ramal de 4 blocos saindo da câmara),
  Raio-X no cursor.
- Prédio de 2 andares de tijolo a sudoeste (x -22..-16, z 16..22): porta ao sul, escada na parede oeste
  passando por um furo no piso, fornalha no térreo, carvoaria no 1º andar. Painel, linha "Prédio":
  Ir ao prédio, Térreo, Paredes baixas, 1º andar (cada um põe o corte na altura certa).
- Os testes automáticos constroem ao norte e no centro: não colocar nada lá.

## Futuro (documentado, sem data)
### Culinária (crafting de comida, estilo Minecraft)
- Estação de cozinha (fogão / forno) com receitas, no mesmo sistema de contas das outras estações.
- Exemplos: sopa de cenoura, pão (trigo), bolo (trigo + outros ingredientes a definir).
- Comida preparada sacia mais que a crua; trigo cru continua sendo comida fraca.
- Novas culturas: batata (e outras depois).
### Estações do ano
- Primavera / verão / outono / inverno afetando crescimento e plantio (ex.: nada cresce no inverno).
- Só depois de amadurecer outros sistemas (comida estocada, casas, frio).
