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

### 10b — Cavernas "espaguete" (túneis)
- Túneis longos e sinuosos de 2 a 5 blocos de largura: ar onde dois ruídos 3D passam juntos perto
  de zero (é o "espaguete" do Minecraft).
- Ficam a partir de 4 blocos abaixo da superfície. Ainda não abrem para fora.
- Ver na depuração: o visualizador de mundo (`run_worldgen_debug.bat`) ganha uma camada "Corte
  vertical", para ver as cavernas de lado.
- Teste: a proporção de ar no subsolo fica numa faixa (ex. 3–8%). A mesma seed gera as mesmas
  cavernas. Os túneis atravessam a borda das colunas sem degrau.

### 10c — Cavernas "queijo" (salões)
- Salões grandes onde um ruído 3D de baixa frequência passa de um limite, com pilares naturais
  (as partes que ficaram sólidas). São mais comuns no fundo.
- Os túneis da 10b ligam os salões.
- Teste: existe pelo menos um salão grande perto do spawn em N seeds, e um aldeão consegue andar
  de uma ponta à outra (navegação).

### 10d — Entradas e ravinas
- Parte dos túneis sobe até a superfície: são as bocas de caverna nas encostas, como no Minecraft.
- Ravinas: fendas estreitas e profundas, raras.
- Nada perto do spawn (raio da área plana inicial), para a colônia não nascer em cima de um buraco.
- Teste: existe entrada a pé de fora para dentro em N seeds, e nenhuma dentro da área inicial.

### 10e — Água e lava no subsolo
- Aquíferos: bolsões com nível de água próprio por região (lagos subterrâneos), e não água vazando
  pelo mapa todo.
- Lava (bloco novo) só nas cavernas mais fundas. É perigosa: aldeões evitam, e ela fica fora da
  navegação.
- **?** Lava agora ou junto com a fase de monstros/perigo?

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
