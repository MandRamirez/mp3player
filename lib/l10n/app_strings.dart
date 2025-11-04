// lib/l10n/app_strings.dart

/// Strings centralizadas para facilitar futura tradução.
class AppStrings {
  // App
  static const appTitle = 'Playlist MP3 App';
  static const homeTitle = 'Playlist MP3';

  // Mensagens genéricas / erros
  static const errorDefault = 'Erro ao carregar playlist';
  static const errorNetwork = 'Sem conexão com a Internet';
  static const errorPlaybackStart = 'Falha ao iniciar reprodução';
  static const errorPlaylistLoad = 'Falha ao carregar playlist';

  // Botões / ações
  static const retryButton = 'Tentar novamente';
  static const refreshTooltip = 'Recarregar playlist';

  // Estados de lista
  static const noTracks = 'Nenhuma música disponível';

  // Estados por faixa
  static const stateDownloadingError = 'Erro no download';
  static const stateBuffering = 'Aguardando buffer...';
  static const statePlaying = 'Reproduzindo';
  static const statePaused = 'Pausado';
  static const stateDownloaded = 'Baixado';
  static const stateDownloading = 'Baixando';

  // Player / controles
  static const playerSectionLabel = 'Controles do reprodutor de áudio';

  static const playLabel = 'Reproduzir';
  static const pauseLabel = 'Pausar';
  static const nextLabel = 'Próxima faixa';
  static const previousLabel = 'Faixa anterior';
  static const shuffleLabel = 'Alternar modo aleatório';
  static const stopLabel = 'Parar reprodução';

  static const repeatOffLabel = 'Repetição desativada';
  static const repeatOneLabel = 'Repetir faixa atual';
  static const repeatAllLabel = 'Repetir todas as faixas';

  static const sliderPositionLabel = 'Posição da faixa';
  static const sliderPositionHint =
      'Arraste para avançar ou voltar na música';

  static String playTrackLabel(String title, String author) =>
      'Reproduzir $title de $author';

  static String pauseTrackLabel(String title, String author) =>
      'Pausar $title de $author';

  static String downloadingPercent(num percent) =>
      '$stateDownloading ${percent.toStringAsFixed(0)}%';
}
