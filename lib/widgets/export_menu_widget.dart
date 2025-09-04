import 'package:flutter/material.dart';
import '../utils/ui_constants.dart';

class ExportMenuWidget extends StatelessWidget {
  final VoidCallback? onExportXML;
  final VoidCallback? onExportFCPXML;
  final VoidCallback? onExportDaVinciXML;
  final VoidCallback? onExportMP4;
  final VoidCallback? onExportSummaryXML;
  final VoidCallback? onExportSummaryFCPXML;
  final VoidCallback? onExportSummaryDaVinciXML;
  final VoidCallback? onExportSummaryMP4;

  const ExportMenuWidget({
    super.key,
    this.onExportXML,
    this.onExportFCPXML,
    this.onExportDaVinciXML,
    this.onExportMP4,
    this.onExportSummaryXML,
    this.onExportSummaryFCPXML,
    this.onExportSummaryDaVinciXML,
    this.onExportSummaryMP4,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      child: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) {
        switch (value) {
          case 'exportXML':
            onExportXML?.call();
            break;
          case 'exportFCPXML':
            onExportFCPXML?.call();
            break;
          case 'exportDaVinciXML':
            onExportDaVinciXML?.call();
            break;
          case 'exportMP4':
            onExportMP4?.call();
            break;
          case 'exportSummaryXML':
            onExportSummaryXML?.call();
            break;
          case 'exportSummaryFCPXML':
            onExportSummaryFCPXML?.call();
            break;
          case 'exportSummaryDaVinciXML':
            onExportSummaryDaVinciXML?.call();
            break;
          case 'exportSummaryMP4':
            onExportSummaryMP4?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'exportXML',
          child: Row(
            children: [
              const Icon(Icons.code, size: 20),
              const SizedBox(width: UIConstants.spacing8),
              const Text('전체 내용 내보내기(프리미어 프로)'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'exportFCPXML',
          child: Row(
            children: [
              const Icon(Icons.movie_creation, size: 20),
              const SizedBox(width: UIConstants.spacing8),
              const Text('전체 내용 내보내기(Final Cut Pro)'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'exportDaVinciXML',
          child: Row(
            children: [
              const Icon(Icons.movie_creation, size: 20),
              const SizedBox(width: UIConstants.spacing8),
              const Text('전체 내용 내보내기(DaVinci Resolve)'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'exportMP4',
          child: Row(
            children: [
              const Icon(Icons.video_file, size: 20),
              const SizedBox(width: UIConstants.spacing8),
              const Text('전체 내용 내보내기(MP4 영상)'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'exportSummaryXML',
          child: Row(
            children: [
              const Icon(Icons.summarize, size: 20),
              const SizedBox(width: UIConstants.spacing8),
              const Text('요약 내용 내보내기(프리미어 프로)'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'exportSummaryFCPXML',
          child: Row(
            children: [
              const Icon(Icons.summarize, size: 20),
              const SizedBox(width: UIConstants.spacing8),
              const Text('요약 내용 내보내기(Final Cut Pro)'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'exportSummaryDaVinciXML',
          child: Row(
            children: [
              const Icon(Icons.summarize, size: 20),
              const SizedBox(width: UIConstants.spacing8),
              const Text('요약 내용 내보내기(DaVinci Resolve)'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'exportSummaryMP4',
          child: Row(
            children: [
              const Icon(Icons.video_file, size: 20),
              const SizedBox(width: UIConstants.spacing8),
              const Text('요약 내용 내보내기(MP4 영상)'),
            ],
          ),
        ),
      ],
    );
  }
}
