//+------------------------------------------------------------------+
//|                                          ExpertLFT.mq5           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Expert LFT - Mini Índice e Mini Dólar"
#property version   "2.00"
#property strict

// CRÍTICO: Conta deve estar em modo HEDGING para múltiplas posições independentes
#define ACCOUNT_MARGIN_MODE_RETAIL_HEDGING 2

#include <Trade\Trade.mqh>

// Parâmetros de entrada
input double LoteInicial = 1.0;        // Lote inicial
input int MaxReversoes = 2;            // Máximo de reversões

// Configurações específicas para Mini Índice (WIN)
input int AlvoWIN = 150;               // Alvo em pontos (WIN)
input int StopWIN = 250;               // Stop em pontos (WIN)

// Configurações específicas para Mini Dólar (WDO)
input int AlvoWDO = 150;               // Alvo em pontos (WDO)
input int StopWDO = 250;               // Stop em pontos (WDO)
input int DiferencaHorarioBrasilia = 0; // Diferença MT para Brasília (ex: MT+3 = digite -3)
input int HoraEncerramento = 17;       // Hora de encerramento das posições (Brasília)
input int MinutoEncerramento = 50;     // Minuto de encerramento das posições (Brasília)
input string ChaveLicenca = "";        // Chave de licença

// Configurações do painel
input color CorFundo = C'20,30,50';           // Cor de fundo do painel
input color CorTitulo = clrBlack;             // Cor do título
input color CorTexto = clrWhiteSmoke;         // Cor do texto
input color CorLabel = clrLightSteelBlue;     // Cor das labels
input color CorLucro = clrLime;               // Cor valores positivos
input color CorPrejuizo = clrRed;             // Cor valores negativos
input int PosX = 10;                          // Posição X
input int PosY = 20;                          // Posição Y

// Variáveis globais
CTrade trade;
bool ordemAberta[4] = {false, false, false, false};
int reversaoAtual[4] = {0, 0, 0, 0};
double loteAtual[4];
ulong ticketAtual[4] = {0, 0, 0, 0};
ulong ultimoDealProcessado[4] = {0, 0, 0, 0}; // Controle de deals já processados
datetime ultimaExecucao[4] = {0, 0, 0, 0}; // Controle de última execução por horário

// Variáveis para detecção de símbolo
bool isMiniDolar = false;
double multiplicadorPontos = 1.0;

// Variáveis de P/L
double plDiario = 0;
double plMensal = 0;
double saldoInicialConta = 0;
double lucroTotal = 0;
datetime dataAtual;
int mesAtual;

// Licença
bool licencaValida = false;
string hardwareID = "";
datetime dataExpiracao = 0;

// Horários de entrada
int horariosEntrada[4][2] = {
   {10, 0},   // 10:00
   {10, 30},  // 10:30
   {11, 0},   // 11:00
   {12, 0}    // 12:00
};

//+------------------------------------------------------------------+
//| Configura esquema de cores do gráfico                           |
//+------------------------------------------------------------------+
void ConfigurarCoresGrafico()
{
   // Fundo branco
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
   
   // Grid e foreground
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);
   ChartSetInteger(0, CHART_COLOR_GRID, clrLightGray);
   
   // Remove grade do gráfico
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   
   // Candles - corpo verde/vermelho e bordas pretas
   ChartSetInteger(0, CHART_COLOR_CHART_UP, clrBlack);        // Borda candle de alta (preto)
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrBlack);      // Borda candle de baixa (preto)
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrLime);     // Corpo candle de alta
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrRed);      // Corpo candle de baixa
   
   // Eixos e escalas
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, clrBlack);
   ChartSetInteger(0, CHART_COLOR_VOLUME, clrGreen);
   ChartSetInteger(0, CHART_COLOR_BID, clrBlue);
   ChartSetInteger(0, CHART_COLOR_ASK, clrRed);
   
   // Força redesenho do gráfico
   ChartRedraw(0);
   
   Print("✓ Esquema de cores aplicado: Fundo branco, candles verde/vermelho");
}

//+------------------------------------------------------------------+
//| Detecta símbolo e configura multiplicador de pontos             |
//+------------------------------------------------------------------+
void DetectarSimbolo()
{
   string simbolo = _Symbol;
   
   // Verifica se é Mini Dólar (WDO)
   if(StringFind(simbolo, "WDO") >= 0)
   {
      isMiniDolar = true;
      // No mini dólar: 1 tick = 0.5 = 500 pontos
      // Para converter pontos de entrada (baseados em WIN) para WDO
      // WIN: 1 ponto = 1, tick = 5 pontos
      // WDO: 1 ponto = 0.001, tick = 0.5 (500 pontos)
      // Multiplicador: 500/5 = 100
      multiplicadorPontos = 100.0;
      Print("═══════════════════════════════════════════════════");
      Print("📊 MINI DÓLAR DETECTADO (WDO)");
      Print("Multiplicador de pontos: ", multiplicadorPontos);
      Print("Tick size: ", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
      Print("Point: ", _Point);
      Print("═══════════════════════════════════════════════════");
   }
   // Verifica se é Mini Índice (WIN)
   else if(StringFind(simbolo, "WIN") >= 0)
   {
      isMiniDolar = false;
      multiplicadorPontos = 1.0;
      Print("═══════════════════════════════════════════════════");
      Print("📊 MINI ÍNDICE DETECTADO (WIN)");
      Print("Multiplicador de pontos: ", multiplicadorPontos);
      Print("Tick size: ", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
      Print("Point: ", _Point);
      Print("═══════════════════════════════════════════════════");
   }
   else
   {
      // Símbolo desconhecido - usa padrão WIN
      isMiniDolar = false;
      multiplicadorPontos = 1.0;
      Print("⚠️ Símbolo não reconhecido: ", simbolo);
      Print("   Usando configuração padrão (WIN)");
   }
}

//+------------------------------------------------------------------+
//| Obtém horário de Brasília convertido do horário do MT            |
//+------------------------------------------------------------------+
MqlDateTime ObterHorarioBrasilia()
{
   MqlDateTime horarioBrasilia;
   datetime tempoBrasilia = TimeCurrent() + (DiferencaHorarioBrasilia * 3600);
   TimeToStruct(tempoBrasilia, horarioBrasilia);
   return horarioBrasilia;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Verifica se a conta está em modo HEDGING
   ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Alert("⚠️ ATENÇÃO: Conta deve estar em modo HEDGING!");
      Print("════════════════════════════════════════════════════");
      Print("❌ ERRO CRÍTICO: Modo de Margem Incorreto");
      Print("════════════════════════════════════════════════════");
      Print("Modo atual: ", EnumToString(marginMode));
      Print("Modo necessário: HEDGING");
      Print("");
      Print("Para corrigir:");
      Print("1. Ferramentas → Opções → Trade");
      Print("2. Altere 'Accounting' para 'Hedging'");
      Print("3. Reinicie o MetaTrader");
      Print("════════════════════════════════════════════════════");
   }
   
   // Gera Hardware ID
   hardwareID = GerarHardwareID();
   
   // Valida licença
   licencaValida = ValidarLicenca(ChaveLicenca);
   
   if(!licencaValida)
   {
      string msg = "╔════════════════════════════════════════╗\n";
      msg += "║        LICENÇA INVÁLIDA OU EXPIRADA!   ║\n";
      msg += "╚════════════════════════════════════════╝\n\n";
      msg += "Hardware ID da sua conta:\n";
      msg += hardwareID + "\n\n";
      msg += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
      msg += "Entre em contato para ativar sua licença:\n";
      msg += "Site: tradereb.com.br\n";
      msg += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n";
      msg += "Envie seu Hardware ID para receber a chave";
      
      MessageBox(msg, "Robô Reversão WIN - Ativação", MB_OK | MB_ICONWARNING);
      
      Print("═══════════════════════════════════════════════════");
      Print("LICENÇA NÃO ATIVADA");
      Print("═══════════════════════════════════════════════════");
      Print("Hardware ID: ", hardwareID);
      Print("Entre em contato: tradereb.com.br");
      Print("═══════════════════════════════════════════════════");
      
      return(INIT_FAILED);
   }
   
   // Licença OK - continua inicialização
   Print("═══════════════════════════════════════════════════");
   Print("LICENÇA ATIVADA COM SUCESSO!");
   Print("Hardware ID: ", hardwareID);
   Print("═══════════════════════════════════════════════════");
   
   // Detecta símbolo e configura multiplicador de pontos
   DetectarSimbolo();
   
   // Configura esquema de cores do gráfico
   ConfigurarCoresGrafico();
   
   // Exibe informações de fuso horário
   MqlDateTime horarioMT, horarioBR;
   TimeToStruct(TimeCurrent(), horarioMT);
   horarioBR = ObterHorarioBrasilia();
   
   Print("═══════════════════════════════════════════════════");
   Print("CONFIGURAÇÃO DE FUSO HORÁRIO");
   Print("═══════════════════════════════════════════════════");
   Print("Horário do MetaTrader: ", StringFormat("%02d:%02d", horarioMT.hour, horarioMT.min));
   Print("Horário de Brasília: ", StringFormat("%02d:%02d", horarioBR.hour, horarioBR.min));
   Print("Diferença configurada: ", DiferencaHorarioBrasilia, " horas");
   Print("═══════════════════════════════════════════════════");
   Print("Horários de entrada (Brasília): 10:00, 10:30, 11:00, 12:00");
   Print("Horário de encerramento: ", StringFormat("%02d:%02d", HoraEncerramento, MinutoEncerramento));
   Print("───────────────────────────────────────────────────");
   Print("Configurações WIN: Alvo=", AlvoWIN, " | Stop=", StopWIN);
   Print("Configurações WDO: Alvo=", AlvoWDO, " | Stop=", StopWDO);
   Print("═══════════════════════════════════════════════════");
   
   // Inicializa lotes
   for(int i = 0; i < 4; i++)
   {
      loteAtual[i] = LoteInicial;
   }
   
   // Define saldo inicial (sempre usa o saldo atual da conta)
   saldoInicialConta = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Inicializa data
   MqlDateTime tempo;
   TimeToStruct(TimeCurrent(), tempo);
   dataAtual = StringToTime(IntegerToString(tempo.year) + "." + 
                            IntegerToString(tempo.mon) + "." + 
                            IntegerToString(tempo.day));
   mesAtual = tempo.mon;
   
   // Cria painel PRIMEIRO (aparece imediatamente com valores default)
   CriarPainel();
   
   // Força redesenho do gráfico
   ChartRedraw(0);
   
   // Calcula P/L inicial (pode demorar se houver muito histórico)
   CalcularPL();
   
   // Atualiza painel com valores calculados
   AtualizarPainel();
   
   // Força redesenho final
   ChartRedraw(0);
   
   Print("Robô Reversão iniciado - Operacional");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove objetos do painel
   ObjectsDeleteAll(0, "Painel_");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!licencaValida) return;
   
   // Verifica se a licença expirou durante execução
   if(dataExpiracao > 0 && TimeCurrent() > dataExpiracao)
   {
      licencaValida = false;
      Alert("⚠️ LICENÇA EXPIROU! Robô será desativado.");
      Print("═══════════════════════════════════════════════════");
      Print("⚠️  LICENÇA EXPIRADA DURANTE EXECUÇÃO!");
      Print("Data de expiração: ", TimeToString(dataExpiracao, TIME_DATE));
      Print("Robô será desativado.");
      Print("Entre em contato para renovação: tradereb.com.br");
      Print("═══════════════════════════════════════════════════");
      return;
   }
   
   // Obtém horário de Brasília (convertido)
   MqlDateTime horarioAtual = ObterHorarioBrasilia();
   
   // Verifica mudança de dia
   datetime dataHoje = StringToTime(IntegerToString(horarioAtual.year) + "." + 
                                     IntegerToString(horarioAtual.mon) + "." + 
                                     IntegerToString(horarioAtual.day));
   
   if(dataHoje != dataAtual)
   {
      plDiario = 0;
      dataAtual = dataHoje;
   }
   
   // Verifica mudança de mês
   if(horarioAtual.mon != mesAtual)
   {
      plMensal = 0;
      mesAtual = horarioAtual.mon;
   }
   
   // Verifica se está no horário de encerramento
   static bool posicoesEncerradas = false;
   if(horarioAtual.hour == HoraEncerramento && 
      horarioAtual.min == MinutoEncerramento && 
      horarioAtual.sec < 5)
   {
      if(!posicoesEncerradas)
      {
         FecharTodasPosicoes();
         posicoesEncerradas = true;
      }
   }
   else if(horarioAtual.hour != HoraEncerramento || horarioAtual.min != MinutoEncerramento)
   {
      posicoesEncerradas = false; // Reset para o próximo dia
   }
   
   // Bloqueia novas entradas após o horário de encerramento
   bool horarioPermitido = true;
   if(horarioAtual.hour > HoraEncerramento || 
      (horarioAtual.hour == HoraEncerramento && horarioAtual.min >= MinutoEncerramento))
   {
      horarioPermitido = false;
   }
   
   // Verifica cada horário programado
   for(int i = 0; i < 4; i++)
   {
      // Calcula timestamp único do minuto atual (sem segundos)
      datetime minutoAtual = StringToTime(IntegerToString(horarioAtual.year) + "." +
                                          IntegerToString(horarioAtual.mon) + "." +
                                          IntegerToString(horarioAtual.day) + " " +
                                          IntegerToString(horarioAtual.hour) + ":" +
                                          IntegerToString(horarioAtual.min) + ":00");
      
      // Verifica se é o horário correto E ainda não executou hoje E está em horário permitido
      if(horarioAtual.hour == horariosEntrada[i][0] && 
         horarioAtual.min == horariosEntrada[i][1] && 
         horarioAtual.sec < 2 &&  // Janela reduzida para 2 segundos
         !ordemAberta[i] &&
         ultimaExecucao[i] != minutoAtual &&  // Garante execução única por minuto
         horarioPermitido)  // Bloqueia após horário de encerramento
      {
         Print("\n🎯 Gatilho de entrada ativado - Horário ", horariosEntrada[i][0], ":", StringFormat("%02d", horariosEntrada[i][1]));
         Print("   Timestamp do minuto: ", TimeToString(minutoAtual, TIME_DATE|TIME_MINUTES));
         Print("   Última execução: ", TimeToString(ultimaExecucao[i], TIME_DATE|TIME_MINUTES));
         
         ultimaExecucao[i] = minutoAtual;  // Marca como executado ANTES de abrir
         AbrirVenda(i);
      }
      
      // Sempre verifica ordens abertas (não depende de ticketAtual)
      if(ordemAberta[i])
      {
         // VERIFICA MANUALMENTE SE ATINGIU SL/TP E FECHA
         VerificarESLTP(i);
         
         // Depois verifica se foi fechada
         VerificarOrdem(i);
      }
   }
   
   // Reset diário às 18:00
   if(horarioAtual.hour == 18 && horarioAtual.min == 0 && horarioAtual.sec < 2)
   {
      ResetDiario();
   }
   
   // Atualiza painel a cada 5 segundos
   static datetime ultimaAtualizacao = 0;
   if(TimeCurrent() - ultimaAtualizacao >= 5)
   {
      CalcularPL();
      AtualizarPainel();
      ultimaAtualizacao = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Gera Hardware ID único baseado em múltiplos fatores              |
//+------------------------------------------------------------------+
string GerarHardwareID()
{
   long account = AccountInfoInteger(ACCOUNT_LOGIN);
   string accountName = AccountInfoString(ACCOUNT_NAME);
   string company = AccountInfoString(ACCOUNT_COMPANY);
   string server = AccountInfoString(ACCOUNT_SERVER);
   
   // Combina múltiplos fatores
   string combined = IntegerToString(account) + accountName + company + server;
   
   // Aplica hash simples
   long hash = 0;
   for(int i = 0; i < StringLen(combined); i++)
   {
      hash = ((hash << 5) - hash) + StringGetCharacter(combined, i);
      hash = hash & hash; // Converte para 32-bit
   }
   
   return IntegerToString(MathAbs(hash));
}

//+------------------------------------------------------------------+
//| Valida licença com algoritmo assimétrico e data de expiração     |
//+------------------------------------------------------------------+
bool ValidarLicenca(string chave)
{
   if(chave == "") return false;
   
   // Remove espaços e traços
   StringReplace(chave, " ", "");
   StringReplace(chave, "-", "");
   StringToUpper(chave);
   
   // Remove prefixo se existir
   if(StringFind(chave, "LIC") == 0)
      chave = StringSubstr(chave, 3);
   
   if(StringLen(chave) != 20) return false;
   
   // Extrai partes da chave (12 dígitos para hardware + 4 dígitos duplicados + 4 para data)
   string parte1 = StringSubstr(chave, 0, 4);   // Hardware check 1
   string parte2 = StringSubstr(chave, 4, 4);   // Hardware check 2
   string parte3 = StringSubstr(chave, 8, 4);   // Hardware check 3
   string parte4 = StringSubstr(chave, 12, 4);  // Duplicata de parte3 (validação extra)
   string parteData = StringSubstr(chave, 16, 4); // Data codificada (últimos 4 dígitos)
   
   // Converte para números
   long p1 = StringToInteger(parte1);
   long p2 = StringToInteger(parte2);
   long p3 = StringToInteger(parte3);
   long p4 = StringToInteger(parte4);
   long pData = StringToInteger(parteData);
   
   // Algoritmo de validação complexo (NÃO REVELAR PARA USUÁRIOS)
   // Chave secreta hardcoded (ofuscada)
   long s1 = 7919; // Primo 1
   long s2 = 6421; // Primo 2
   long s3 = 3929; // Primo 3
   long s4 = 5227; // Primo 4 para data
   
   // Extrai hash do hardware ID e reduz para evitar overflow
   long hwHash = StringToInteger(hardwareID);
   long hwReduced = hwHash % 1000000007; // Usa módulo grande para distribuição
   
   // Calcula valores esperados (aplicando módulo para evitar overflow)
   long check1 = ((hwReduced % 10000) * (s1 % 10000)) % 10000;
   long check2 = (((hwReduced % 10000) * (s2 % 10000)) + s3) % 10000;
   long check3 = (check1 + check2) % 10000;
   
   // Valida se a chave corresponde ao hardware ID
   bool valid1 = (p1 == check1);
   bool valid2 = (p2 == check2);
   bool valid3 = (p3 == check3);
   bool valid4 = (p4 == check3); // Valida que parte4 é duplicata de parte3
   
   if(!valid1 || !valid2 || !valid3 || !valid4) return false;
   
   // Decodifica data de expiração
   // pData contém dias desde 01/01/2024
   datetime base2024 = StringToTime("2024.01.01 00:00:00");
   dataExpiracao = base2024 + (pData * 86400); // 86400 segundos = 1 dia
   
   // Valida se a data é razoável
   MqlDateTime dtCheck;
   TimeToStruct(dataExpiracao, dtCheck);
   
   if(dtCheck.year < 2024 || dtCheck.year > 2050)
      return false;
   
   // Verifica se a licença está expirada
   if(TimeCurrent() > dataExpiracao)
   {
      Print("═══════════════════════════════════════════════════");
      Print("⚠️  LICENÇA EXPIRADA!");
      Print("Data de expiração: ", TimeToString(dataExpiracao, TIME_DATE));
      Print("Data atual: ", TimeToString(TimeCurrent(), TIME_DATE));
      Print("═══════════════════════════════════════════════════");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calcula P/L diário e mensal                                      |
//+------------------------------------------------------------------+
void CalcularPL()
{
   plDiario = 0;
   plMensal = 0;
   
   MqlDateTime hoje;
   TimeToStruct(TimeCurrent(), hoje);
   
   datetime inicioMes = StringToTime(IntegerToString(hoje.year) + "." + 
                                      IntegerToString(hoje.mon) + ".01 00:00:00");
   
   // Seleciona histórico apenas do mês atual (otimização)
   if(!HistorySelect(inicioMes, TimeCurrent()))
   {
      Print("Erro ao selecionar histórico");
      return;
   }
   
   int totalDeals = HistoryDealsTotal();
   
   // Limita processamento para evitar travamento (máximo 1000 deals)
   int maxDeals = MathMin(totalDeals, 1000);
   
   // Calcula P/L de deals fechados (do mais recente para o mais antigo)
   for(int i = totalDeals - 1; i >= totalDeals - maxDeals && i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         
         // Filtra apenas fechamentos do símbolo atual
         if(symbol == _Symbol && dealEntry == DEAL_ENTRY_OUT)
         {
            double lucro = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double comissao = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
            datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            
            double lucroLiquido = lucro + comissao + swap;
            
            if(dealTime >= dataAtual)
            {
               plDiario += lucroLiquido;
            }
            
            if(dealTime >= inicioMes)
            {
               plMensal += lucroLiquido;
            }
         }
      }
   }
   
   // Adiciona P/L flutuante de posições abertas
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double lucroFlutuante = PositionGetDouble(POSITION_PROFIT);
            double swapFlutuante = PositionGetDouble(POSITION_SWAP);
            
            plDiario += (lucroFlutuante + swapFlutuante);
            plMensal += (lucroFlutuante + swapFlutuante);
         }
      }
   }
   
   lucroTotal = AccountInfoDouble(ACCOUNT_BALANCE) + plDiario - saldoInicialConta;
}

//+------------------------------------------------------------------+
//| Cria painel visual                                               |
//+------------------------------------------------------------------+
void CriarPainel()
{
   // Remove objetos antigos primeiro (caso estejam presentes)
   ObjectsDeleteAll(0, "Painel_");
   
   int largura = 340;
   int altura = 380;
   int linhaY = PosY;
   
   // Fundo principal com borda
   if(!ObjectCreate(0, "Painel_Borda", OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      Print("Aviso: Erro ao criar Painel_Borda: ", GetLastError());
   }
   ObjectSetInteger(0, "Painel_Borda", OBJPROP_XDISTANCE, PosX + 4);
   ObjectSetInteger(0, "Painel_Borda", OBJPROP_YDISTANCE, PosY - 2);
   ObjectSetInteger(0, "Painel_Borda", OBJPROP_XSIZE, largura + 4);
   ObjectSetInteger(0, "Painel_Borda", OBJPROP_YSIZE, altura + 4);
   ObjectSetInteger(0, "Painel_Borda", OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, "Painel_Borda", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "Painel_Borda", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "Painel_Borda", OBJPROP_BACK, false);
   
   // Painel principal
   if(!ObjectCreate(0, "Painel_Fundo", OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      Print("Aviso: Erro ao criar Painel_Fundo: ", GetLastError());
   }
   ObjectSetInteger(0, "Painel_Fundo", OBJPROP_XDISTANCE, PosX);
   ObjectSetInteger(0, "Painel_Fundo", OBJPROP_YDISTANCE, PosY);
   ObjectSetInteger(0, "Painel_Fundo", OBJPROP_XSIZE, largura);
   ObjectSetInteger(0, "Painel_Fundo", OBJPROP_YSIZE, altura);
   ObjectSetInteger(0, "Painel_Fundo", OBJPROP_BGCOLOR, CorFundo);
   ObjectSetInteger(0, "Painel_Fundo", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "Painel_Fundo", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "Painel_Fundo", OBJPROP_BACK, false);
   
   // Cabeçalho preto
   if(!ObjectCreate(0, "Painel_Header", OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      Print("Aviso: Erro ao criar Painel_Header: ", GetLastError());
   }
   ObjectSetInteger(0, "Painel_Header", OBJPROP_XDISTANCE, PosX);
   ObjectSetInteger(0, "Painel_Header", OBJPROP_YDISTANCE, PosY);
   ObjectSetInteger(0, "Painel_Header", OBJPROP_XSIZE, largura);
   ObjectSetInteger(0, "Painel_Header", OBJPROP_YSIZE, 50);
   ObjectSetInteger(0, "Painel_Header", OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, "Painel_Header", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "Painel_Header", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "Painel_Header", OBJPROP_BACK, false);
   
   linhaY = PosY + 20;
   
   // Título
   CriarTexto("Painel_Titulo", "Expert LFT", PosX + largura/2, linhaY, 14, clrWhite, true, ANCHOR_CENTER);
   
   linhaY += 40;
   
   // Linha separadora
   CriarLinha("Painel_Sep0", PosX + 10, linhaY, largura - 20, clrDimGray);
   
   linhaY += 15;
   
   // Estratégia
   CriarTexto("Painel_Label_Estrategia", "Estratégia Ativar", PosX + 15, linhaY, 9, CorLabel, false);
   CriarTexto("Painel_Valor_Estrategia", ": Carregando...", PosX + 140, linhaY, 9, clrGold, true);
   
   linhaY += 20;
   
   // Número da Conta (alterado de Nome do Usuário)
   CriarTexto("Painel_Label_Usuario", "Número da Conta", PosX + 15, linhaY, 9, CorLabel, false);
   long numeroConta = AccountInfoInteger(ACCOUNT_LOGIN);
   CriarTexto("Painel_Valor_Usuario", ": " + IntegerToString(numeroConta), PosX + 140, linhaY, 9, clrGold, false);
   
   linhaY += 20;
   
   // Data vencimento
   CriarTexto("Painel_Label_Vencimento", "Data vencimento", PosX + 15, linhaY, 9, CorLabel, false);
   string dataVenc = "Não ativada";
   color corVenc = clrOrangeRed;
   if(dataExpiracao > 0)
   {
      MqlDateTime dtExp;
      TimeToStruct(dataExpiracao, dtExp);
      
      // Verifica se é licença vitalícia (ano >= 2050)
      if(dtExp.year >= 2050)
      {
         dataVenc = "Vitalícia";
         corVenc = clrLime;
      }
      else
      {
         dataVenc = TimeToString(dataExpiracao, TIME_DATE);
         // Verifica quantos dias faltam
         int diasRestantes = (int)((dataExpiracao - TimeCurrent()) / 86400);
         if(diasRestantes > 30)
            corVenc = clrLime;
         else if(diasRestantes > 7)
            corVenc = clrYellow;
         else
            corVenc = clrOrangeRed;
      }
   }
   CriarTexto("Painel_Valor_Vencimento", ": " + dataVenc, PosX + 140, linhaY, 9, corVenc, true);
   
   linhaY += 25;
   
   // Linha separadora
   CriarLinha("Painel_Sep1", PosX + 10, linhaY, largura - 20, clrDimGray);
   
   linhaY += 15;
   
   CriarTexto("Painel_Label_Timeframe", "TimeFrame", PosX + 15, linhaY, 9, CorLabel, false);
   CriarTexto("Painel_Valor_Timeframe", ": " + PeriodoParaString(), PosX + 140, linhaY, 9, CorTexto, false);
   
   linhaY += 20;
   
   // Horário Atual (Brasília)
   MqlDateTime dt = ObterHorarioBrasilia();
   string horaAtual = StringFormat("%02d:%02d", dt.hour, dt.min);
   
   CriarTexto("Painel_Label_Horario", "Horário Brasília", PosX + 15, linhaY, 9, CorLabel, false);
   CriarTexto("Painel_Valor_Horario", ": " + horaAtual, PosX + 140, linhaY, 9, CorTexto, false);
   
   linhaY += 25;
   
   // Linha separadora
   CriarLinha("Painel_Sep2", PosX + 10, linhaY, largura - 20, clrDimGray);
   
   linhaY += 15;
   
   // Saldo Inicial
   CriarTexto("Painel_Label_SaldoInicial", "Saldo Inicial", PosX + 15, linhaY, 9, CorLabel, false);
   CriarTexto("Painel_Valor_SaldoInicial", ": R$ 0,00", PosX + 140, linhaY, 9, CorTexto, false);
   
   linhaY += 20;
   
   // Saldo Total
   CriarTexto("Painel_Label_SaldoTotal", "Saldo Total", PosX + 15, linhaY, 10, CorLabel, true);
   CriarTexto("Painel_Valor_SaldoTotal", ": R$ 0,00", PosX + 140, linhaY, 10, CorLucro, true);
   
   linhaY += 25;
   
   // P/L Diário
   CriarTexto("Painel_Label_Diario", "P/L Diário", PosX + 15, linhaY, 9, CorLabel, false);
   CriarTexto("Painel_Valor_Diario", ": R$ 0,00", PosX + 140, linhaY, 9, CorTexto, false);
   
   linhaY += 20;
   
   // P/L Mensal
   CriarTexto("Painel_Label_Mensal", "P/L Mensal", PosX + 15, linhaY, 9, CorLabel, false);
   CriarTexto("Painel_Valor_Mensal", ": R$ 0,00", PosX + 140, linhaY, 9, CorTexto, false);
   
   linhaY += 20;
   
   // Status operacional
   CriarTexto("Painel_Label_Status", "Status", PosX + 15, linhaY, 9, CorLabel, false);
   CriarTexto("Painel_Valor_Status", ": Aguardando", PosX + 140, linhaY, 9, CorLucro, true);
   
   linhaY += 20;
   
   CriarTexto("Painel_Label_Operacoes", "Operações Ativas", PosX + 15, linhaY, 9, CorLabel, false);
   CriarTexto("Painel_Valor_Operacoes", ": 0", PosX + 140, linhaY, 9, CorTexto, false);

   
   linhaY += 25;

   // Site
   CriarTexto("Painel_Site", "WWW.TRADEREB.COM.BR", PosX + 15, linhaY, 9, clrDodgerBlue, true);
   
   
   Print("✓ Painel criado com sucesso");
}

//+------------------------------------------------------------------+
//| Converte período do gráfico para string                         |
//+------------------------------------------------------------------+
string PeriodoParaString()
{
   int periodo = Period();
   
   switch(periodo)
   {
      case PERIOD_M1:  return "M 1.0";
      case PERIOD_M5:  return "M 5.0";
      case PERIOD_M15: return "M 15.0";
      case PERIOD_M30: return "M 30.0";
      case PERIOD_H1:  return "H 1.0";
      case PERIOD_H4:  return "H 4.0";
      case PERIOD_D1:  return "D 1.0";
      case PERIOD_W1:  return "W 1.0";
      case PERIOD_MN1: return "MN 1.0";
      default: return "M " + IntegerToString(periodo);
   }
}

//+------------------------------------------------------------------+
//| Cria linha separadora                                            |
//+------------------------------------------------------------------+
void CriarLinha(string nome, int x, int y, int comprimento, color cor)
{
   ObjectCreate(0, nome, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_XSIZE, comprimento);
   ObjectSetInteger(0, nome, OBJPROP_YSIZE, 1);
   ObjectSetInteger(0, nome, OBJPROP_BGCOLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, nome, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nome, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Cria texto no painel                                             |
//+------------------------------------------------------------------+
void CriarTexto(string nome, string texto, int x, int y, int tamanho, color cor, bool negrito, ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   ObjectCreate(0, nome, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nome, OBJPROP_ANCHOR, anchor);
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
   ObjectSetString(0, nome, OBJPROP_FONT, negrito ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, tamanho);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
}

//+------------------------------------------------------------------+
//| Atualiza painel                                                  |
//+------------------------------------------------------------------+
void AtualizarPainel()
{
   // Atualiza horário (usando horário de Brasília)
   MqlDateTime dt = ObterHorarioBrasilia();
   string horaAtual = StringFormat("%02d:%02d", dt.hour, dt.min);
   ObjectSetString(0, "Painel_Valor_Horario", OBJPROP_TEXT, ": " + horaAtual);
   
   // Atualiza estratégia com o ativo atual
   string ativo = isMiniDolar ? "WDO (Mini Dólar)" : "WIN (Mini Índice)";
   ObjectSetString(0, "Painel_Valor_Estrategia", OBJPROP_TEXT, ": " + ativo);
   
   // Atualiza data de vencimento com cor dinâmica
   if(dataExpiracao > 0)
   {
      MqlDateTime dtExp;
      TimeToStruct(dataExpiracao, dtExp);
      
      // Se for vitalícia, sempre verde
      if(dtExp.year >= 2050)
      {
         ObjectSetInteger(0, "Painel_Valor_Vencimento", OBJPROP_COLOR, clrLime);
      }
      else
      {
         int diasRestantes = (int)((dataExpiracao - TimeCurrent()) / 86400);
         color corVenc;
         if(diasRestantes > 30)
            corVenc = clrLime;
         else if(diasRestantes > 7)
            corVenc = clrYellow;
         else
            corVenc = clrOrangeRed;
         
         ObjectSetInteger(0, "Painel_Valor_Vencimento", OBJPROP_COLOR, corVenc);
      }
   }
   
   // Saldo Inicial
   ObjectSetString(0, "Painel_Valor_SaldoInicial", OBJPROP_TEXT, ": R$ " + DoubleToString(saldoInicialConta, 2));
   
   // Lucro Total
   color corLucro = (lucroTotal >= 0) ? CorLucro : CorPrejuizo;
   string sinalLucro = (lucroTotal >= 0) ? "+" : "";
   ObjectSetString(0, "Painel_Valor_Lucro", OBJPROP_TEXT, ": R$ " + sinalLucro + DoubleToString(lucroTotal, 2));
   ObjectSetInteger(0, "Painel_Valor_Lucro", OBJPROP_COLOR, corLucro);
   
   // Saldo Total
   double saldoTotal = AccountInfoDouble(ACCOUNT_BALANCE);
   color corSaldoTotal = (saldoTotal >= saldoInicialConta) ? CorLucro : CorPrejuizo;
   ObjectSetString(0, "Painel_Valor_SaldoTotal", OBJPROP_TEXT, ": R$ " + DoubleToString(saldoTotal, 2));
   ObjectSetInteger(0, "Painel_Valor_SaldoTotal", OBJPROP_COLOR, corSaldoTotal);
   
   // P/L Diário
   color corDiario = (plDiario >= 0) ? CorLucro : CorPrejuizo;
   string sinalDiario = (plDiario >= 0) ? "+" : "";
   ObjectSetString(0, "Painel_Valor_Diario", OBJPROP_TEXT, ": R$ " + sinalDiario + DoubleToString(plDiario, 2));
   ObjectSetInteger(0, "Painel_Valor_Diario", OBJPROP_COLOR, corDiario);
   
   // P/L Mensal
   color corMensal = (plMensal >= 0) ? CorLucro : CorPrejuizo;
   string sinalMensal = (plMensal >= 0) ? "+" : "";
   ObjectSetString(0, "Painel_Valor_Mensal", OBJPROP_TEXT, ": R$ " + sinalMensal + DoubleToString(plMensal, 2));
   ObjectSetInteger(0, "Painel_Valor_Mensal", OBJPROP_COLOR, corMensal);
   
   // Operações ativas
   int opAtivas = 0;
   for(int i = 0; i < 4; i++)
   {
      if(ordemAberta[i]) opAtivas++;
   }
   ObjectSetString(0, "Painel_Valor_Operacoes", OBJPROP_TEXT, ": " + IntegerToString(opAtivas));
   
   // Status
   string status = "Aguardando";
   color corStatus = CorTexto;
   if(opAtivas > 0)
   {
      status = "Operando";
      corStatus = CorLucro;
   }
   ObjectSetString(0, "Painel_Valor_Status", OBJPROP_TEXT, ": " + status);
   ObjectSetInteger(0, "Painel_Valor_Status", OBJPROP_COLOR, corStatus);
}

//+------------------------------------------------------------------+
//| Fecha todas as posições abertas (final do pregão)                |
//+------------------------------------------------------------------+
void FecharTodasPosicoes()
{
   Print("\n╔═══════════════════════════════════════════════════╗");
   Print("║   🔴 ENCERRAMENTO DO PREGÃO - FECHANDO POSIÇÕES   ║");
   Print("╚═══════════════════════════════════════════════════╝\n");
   
   int totalFechadas = 0;
   
   // Fecha todas as posições do símbolo atual
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            if(trade.PositionClose(posTicket))
            {
               Print("✓ Posição #", posTicket, " fechada | Tipo: ", 
                     (tipo == POSITION_TYPE_BUY ? "COMPRA" : "VENDA"), 
                     " | P/L: ", DoubleToString(profit, 2));
               totalFechadas++;
            }
            else
            {
               Print("❌ Erro ao fechar posição #", posTicket, ": ", GetLastError());
            }
         }
      }
   }
   
   // Reseta variáveis de controle de todos os horários
   for(int i = 0; i < 4; i++)
   {
      ordemAberta[i] = false;
      reversaoAtual[i] = 0;
      loteAtual[i] = LoteInicial;
      ticketAtual[i] = 0;
      ultimoDealProcessado[i] = 0;
   }
   
   Print("\n📊 Total de posições fechadas: ", totalFechadas);
   Print("═══════════════════════════════════════════════════\n");
   
   // Atualiza P/L final
   CalcularPL();
   AtualizarPainel();
}

//+------------------------------------------------------------------+
//| Abre ordem de venda                                              |
//+------------------------------------------------------------------+
void AbrirVenda(int indice)
{
   double preco = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Seleciona valores de Stop e Alvo baseado no símbolo
   int stopPontos = isMiniDolar ? StopWDO : StopWIN;
   int alvoPontos = isMiniDolar ? AlvoWDO : AlvoWIN;
   
   // Ajusta pontos de acordo com o símbolo (WIN ou WDO)
   double stopAjustado = stopPontos * multiplicadorPontos * _Point;
   double alvoAjustado = alvoPontos * multiplicadorPontos * _Point;
   
   double sl = preco + stopAjustado;
   double tp = preco - alvoAjustado;
   
   // Normaliza preços
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   // Define magic number único por horário
   int magicNumber = 100000 + indice;
   trade.SetExpertMagicNumber(magicNumber);
   
   if(trade.Sell(loteAtual[indice], _Symbol, preco, sl, tp, "Rev_" + IntegerToString(indice)))
   {
      ulong ticket = trade.ResultDeal();
      
      Print("═══════════════════════════════════════");
      Print("📉 VENDA ABERTA");
      Print("Ticket: #", ticket);
      Print("Símbolo: ", _Symbol, " (", (isMiniDolar ? "Mini Dólar" : "Mini Índice"), ")");
      Print("Horário: ", horariosEntrada[indice][0], ":", StringFormat("%02d", horariosEntrada[indice][1]));
      Print("Lote: ", loteAtual[indice]);
      Print("Preço: ", preco);
      Print("SL: ", sl, " (", stopPontos, " pontos x ", multiplicadorPontos, ")");
      Print("TP: ", tp, " (", alvoPontos, " pontos x ", multiplicadorPontos, ")");
      Print("Reversão: ", reversaoAtual[indice], "/", MaxReversoes);
      Print("Magic Number: ", magicNumber);
      Print("Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      Print("═══════════════════════════════════════");
      
      ordemAberta[indice] = true;
      
      // Aguarda um pouco e verifica se a posição realmente tem SL/TP
      Sleep(100);
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong posTicket = PositionGetTicket(i);
         if(posTicket > 0)
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == magicNumber)
            {
               double posSL = PositionGetDouble(POSITION_SL);
               double posTP = PositionGetDouble(POSITION_TP);
               Print("✓ Posição aberta com SL=", posSL, " TP=", posTP);
               break;
            }
         }
      }
   }
   else
   {
      Print("❌ Erro ao abrir venda: ", GetLastError(), " - ", trade.ResultRetcodeDescription());
      Print("   Retcode: ", trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Abre ordem de compra (reversão)                                 |
//+------------------------------------------------------------------+
void AbrirCompra(int indice)
{
   double preco = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Seleciona valores de Stop e Alvo baseado no símbolo
   int stopPontos = isMiniDolar ? StopWDO : StopWIN;
   int alvoPontos = isMiniDolar ? AlvoWDO : AlvoWIN;
   
   // Ajusta pontos de acordo com o símbolo (WIN ou WDO)
   double stopAjustado = stopPontos * multiplicadorPontos * _Point;
   double alvoAjustado = alvoPontos * multiplicadorPontos * _Point;
   
   double sl = preco - stopAjustado;
   double tp = preco + alvoAjustado;
   
   // Normaliza preços
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   // Define magic number único por horário
   int magicNumber = 100000 + indice;
   trade.SetExpertMagicNumber(magicNumber);
   
   if(trade.Buy(loteAtual[indice], _Symbol, preco, sl, tp, "Rev_" + IntegerToString(indice)))
   {
      ulong ticket = trade.ResultDeal();
      
      Print("═══════════════════════════════════════");
      Print("📈 COMPRA ABERTA (Reversão)");
      Print("Ticket: #", ticket);
      Print("Símbolo: ", _Symbol, " (", (isMiniDolar ? "Mini Dólar" : "Mini Índice"), ")");
      Print("Lote: ", loteAtual[indice]);
      Print("Preço: ", preco);
      Print("SL: ", sl, " (", stopPontos, " pontos x ", multiplicadorPontos, ")");
      Print("TP: ", tp, " (", alvoPontos, " pontos x ", multiplicadorPontos, ")");
      Print("Reversão: ", reversaoAtual[indice], "/", MaxReversoes);
      Print("Magic Number: ", magicNumber);
      Print("Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      Print("═══════════════════════════════════════");
      
      ordemAberta[indice] = true;
      
      // Aguarda um pouco e verifica se a posição realmente tem SL/TP
      Sleep(100);
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong posTicket = PositionGetTicket(i);
         if(posTicket > 0)
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == magicNumber)
            {
               double posSL = PositionGetDouble(POSITION_SL);
               double posTP = PositionGetDouble(POSITION_TP);
               Print("✓ Posição aberta com SL=", posSL, " TP=", posTP);
               break;
            }
         }
      }
   }
   else
   {
      Print("❌ Erro ao abrir compra: ", GetLastError(), " - ", trade.ResultRetcodeDescription());
      Print("   Retcode: ", trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Verifica se SL ou TP foi atingido e fecha manualmente            |
//+------------------------------------------------------------------+
void VerificarESLTP(int indice)
{
   int magicNumber = 100000 + indice;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
      
      ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double precoAtual = tipo == POSITION_TYPE_BUY ? 
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      
      bool deveFechar = false;
      bool foiStopLoss = false;
      string motivo = "";
      
      // Verifica se atingiu SL ou TP
      if(tipo == POSITION_TYPE_SELL)
      {
         if(sl > 0 && precoAtual >= sl)
         {
            deveFechar = true;
            foiStopLoss = true;
            motivo = "STOP LOSS";
         }
         else if(tp > 0 && precoAtual <= tp)
         {
            deveFechar = true;
            foiStopLoss = false;
            motivo = "TAKE PROFIT";
         }
      }
      else if(tipo == POSITION_TYPE_BUY)
      {
         if(sl > 0 && precoAtual <= sl)
         {
            deveFechar = true;
            foiStopLoss = true;
            motivo = "STOP LOSS";
         }
         else if(tp > 0 && precoAtual >= tp)
         {
            deveFechar = true;
            foiStopLoss = false;
            motivo = "TAKE PROFIT";
         }
      }
      
      if(deveFechar)
      {
         Print("\n⚡ ", motivo, " ATINGIDO - Fechando posição #", posTicket);
         Print("   Tipo: ", (tipo == POSITION_TYPE_BUY ? "COMPRA" : "VENDA"));
         Print("   Preço atual: ", precoAtual);
         Print("   SL: ", sl, " | TP: ", tp);
         
         // Fecha a posição
         if(trade.PositionClose(posTicket))
         {
            Print("   ✓ Posição fechada com sucesso!");
            
            // Se foi STOP LOSS e ainda tem reversões disponíveis, faz a reversão IMEDIATAMENTE
            if(foiStopLoss && reversaoAtual[indice] < MaxReversoes)
            {
               Print("\n🔄 INICIANDO REVERSÃO ", reversaoAtual[indice] + 1, "/", MaxReversoes);
               Print("📊 Lote atual: ", DoubleToString(loteAtual[indice], 2));
               
               // Mantém o lote inicial (não dobra mais)
               loteAtual[indice] = LoteInicial;
               reversaoAtual[indice]++;
               
               Print("📊 Lote mantido (inicial): ", DoubleToString(loteAtual[indice], 2));
               Print("📊 Nova reversão: ", reversaoAtual[indice]);
               
               Sleep(500);
               
               // Inverte a direção (a favor do movimento que causou o stop)
               if(tipo == POSITION_TYPE_SELL)
               {
                  // Fechou VENDA, preço subiu e bateu stop = abre COMPRA
                  Print("➡️  Abrindo COMPRA (reversão)\n");
                  AbrirCompra(indice);
               }
               else if(tipo == POSITION_TYPE_BUY)
               {
                  // Fechou COMPRA, preço caiu e bateu stop = abre VENDA  
                  Print("➡️  Abrindo VENDA (reversão)\n");
                  AbrirVenda(indice);
               }
            }
            else if(foiStopLoss)
            {
               // Atingiu máximo de reversões
               Print("\n⛔ MÁXIMO DE REVERSÕES ATINGIDO!\n");
               ordemAberta[indice] = false;
               reversaoAtual[indice] = 0;
               loteAtual[indice] = LoteInicial;
               ultimoDealProcessado[indice] = 0;
            }
            else
            {
               // Foi TAKE PROFIT - finalizou com lucro
               Print("\n✅ GAIN ATINGIDO!\n");
               ordemAberta[indice] = false;
               reversaoAtual[indice] = 0;
               loteAtual[indice] = LoteInicial;
               ultimoDealProcessado[indice] = 0;
            }
         }
         else
         {
            Print("   ❌ Erro ao fechar posição: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Verifica status da ordem                                         |
//+------------------------------------------------------------------+
void VerificarOrdem(int indice)
{
   int magicNumber = 100000 + indice;
   
   // Primeiro verifica se ainda tem posição aberta usando a API correta do MQL5
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong posTicket = PositionGetTicket(i); // Seleciona a posição pelo índice
      if(posTicket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == magicNumber)
         {
            // Posição ainda está aberta
            return;
         }
      }
   }
   
   // Não tem posição aberta - verifica se foi fechada (busca desde o início do dia)
   if(!HistorySelect(dataAtual, TimeCurrent()))
   {
      Print("⚠️ Erro ao selecionar histórico para verificação");
      return;
   }
   
   // Verifica deals no histórico (do mais recente para o mais antigo)
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      
      // Pula se já processamos este deal
      if(dealTicket == ultimoDealProcessado[indice]) break;
      
      // Verifica se é do nosso símbolo e magic number
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != magicNumber) continue;
      
      // Verifica se é saída (fechamento)
      ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT) continue;
      
      // Marca como processado ANTES de processar
      ultimoDealProcessado[indice] = dealTicket;
      
      // Pega informações do fechamento
      double lucro = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double comissao = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double lucroLiquido = lucro + comissao + swap;
      
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      
      Print("\n┌────────────────────────────────────────────────┐");
      Print("│ ⚡ POSIÇÃO FECHADA - Horário ", horariosEntrada[indice][0], ":", StringFormat("%02d", horariosEntrada[indice][1]), "        │");
      Print("├────────────────────────────────────────────────┤");
      Print("│ Deal #", dealTicket, "                                    │");
      Print("│ Tipo deal: ", (dealType == DEAL_TYPE_BUY ? "BUY (fechou venda)" : "SELL (fechou compra)"), "        │");
      Print("│ Resultado: ", (lucroLiquido >= 0 ? "+" : ""), DoubleToString(lucroLiquido, 2), " USD                  │");
      Print("│ Reversão atual: ", reversaoAtual[indice], "/", MaxReversoes, "                        │");
      Print("└────────────────────────────────────────────────┘");
      
      // Verifica se precisa fazer reversão (prejuízo e ainda tem reversões disponíveis)
      if(lucroLiquido < 0 && reversaoAtual[indice] < MaxReversoes)
      {
         Print("\n🔄 INICIANDO REVERSÃO ", reversaoAtual[indice] + 1, "/", MaxReversoes);
         Print("📊 Lote atual: ", DoubleToString(loteAtual[indice], 2));
         
         // Mantém o lote inicial (não dobra mais)
         loteAtual[indice] = LoteInicial;
         reversaoAtual[indice]++;
         
         Print("📊 Lote mantido (inicial): ", DoubleToString(loteAtual[indice], 2));
         Print("📊 Nova reversão: ", reversaoAtual[indice]);
         
         Sleep(500);
         
         // Inverte a direção (a favor do movimento que causou o stop)
         // Nota: deal BUY = fechou venda | deal SELL = fechou compra
         if(dealType == DEAL_TYPE_BUY)
         {
            // Fechou VENDA (deal BUY), preço subiu e bateu stop = abre COMPRA
            Print("➡️  Abrindo COMPRA (reversão)\n");
            AbrirCompra(indice);
         }
         else if(dealType == DEAL_TYPE_SELL)
         {
            // Fechou COMPRA (deal SELL), preço caiu e bateu stop = abre VENDA  
            Print("➡️  Abrindo VENDA (reversão)\n");
            AbrirVenda(indice);
         }
      }
      else
      {
         // Finalizou o ciclo (gain ou máx reversões)
         if(lucroLiquido > 0)
         {
            Print("\n✅ GAIN ATINGIDO! Lucro: ", DoubleToString(lucroLiquido, 2), " USD\n");
         }
         else
         {
            Print("\n⛔ MÁXIMO DE REVERSÕES ATINGIDO! Prejuízo final: ", DoubleToString(lucroLiquido, 2), " USD\n");
         }
         
         // Reset das variáveis deste horário
         ordemAberta[indice] = false;
         reversaoAtual[indice] = 0;
         loteAtual[indice] = LoteInicial;
         ultimoDealProcessado[indice] = 0;
      }
      
      // Atualiza P/L e painel
      CalcularPL();
      AtualizarPainel();
      
      return; // Encontrou e processou, sai da função
   }
}

//+------------------------------------------------------------------+
//| Reset diário                                                     |
//+------------------------------------------------------------------+
void ResetDiario()
{
   Print("\n┌", StringFill(50, '─'), "┐");
   Print("│ RESET DIÁRIO - ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), StringFill(18, ' '), "│");
   Print("└", StringFill(50, '─'), "┘\n");
   
   for(int i = 0; i < 4; i++)
   {
      ordemAberta[i] = false;
      reversaoAtual[i] = 0;
      loteAtual[i] = LoteInicial;
      ticketAtual[i] = 0;
      ultimoDealProcessado[i] = 0;
      ultimaExecucao[i] = 0;  // Limpa controle de execução
   }
   
   CalcularPL();
   AtualizarPainel();
   
   Print("Reset realizado com sucesso!");
}

//+------------------------------------------------------------------+
//| Retorna string preenchida com caractere                          |
//+------------------------------------------------------------------+
string StringFill(int count, ushort character)
{
   string result = "";
   for(int i = 0; i < count; i++)
      result += ShortToString(character);
   return result;
}
//+------------------------------------------------------------------+