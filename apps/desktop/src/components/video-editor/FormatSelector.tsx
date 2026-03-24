import { Film, Image } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { ExportFormat } from '@/lib/exporter/types';

interface FormatSelectorProps {
  selectedFormat: ExportFormat;
  onFormatChange: (format: ExportFormat) => void;
  disabled?: boolean;
}

interface FormatOption {
  value: ExportFormat;
  label: string;
  description: string;
  icon: React.ReactNode;
}

const formatOptions: FormatOption[] = [
  {
    value: 'mp4',
    label: 'MP4 Video',
    description: 'High quality video file',
    icon: <Film className="w-5 h-5" />,
  },
  {
    value: 'gif',
    label: 'GIF Animation',
    description: 'Animated image for sharing',
    icon: <Image className="w-5 h-5" />,
  },
];

export function FormatSelector({
  selectedFormat,
  onFormatChange,
  disabled = false,
}: FormatSelectorProps) {
  return (
    <div className="grid grid-cols-2 gap-3">
      {formatOptions.map((option) => {
        const isSelected = selectedFormat === option.value;
        return (
          <button
            key={option.value}
            type="button"
            disabled={disabled}
            onClick={() => onFormatChange(option.value)}
            className={cn(
              'relative flex flex-col items-center gap-2 p-4 rounded-xl border transition-all duration-200',
              'focus:outline-none focus:ring-2 focus:ring-[#2563EB]/50 focus:ring-offset-2 focus:ring-offset-[#09090b]',
              isSelected
                ? 'bg-[#2563EB]/10 border-[#2563EB]/50 text-white'
                : 'bg-white/5 border-white/10 text-slate-400 hover:bg-white/10 hover:border-white/20 hover:text-slate-200',
              disabled && 'opacity-50 cursor-not-allowed'
            )}
          >
            <div
              className={cn(
                'w-10 h-10 rounded-full flex items-center justify-center transition-colors',
                isSelected ? 'bg-[#2563EB]/20 text-[#2563EB]' : 'bg-white/5'
              )}
            >
              {option.icon}
            </div>
            <div className="text-center">
              <div className="font-medium text-sm">{option.label}</div>
              <div className="text-xs text-slate-500 mt-0.5">{option.description}</div>
            </div>
            {isSelected && (
              <div className="absolute top-2 right-2 w-2 h-2 rounded-full bg-[#2563EB]" />
            )}
          </button>
        );
      })}
    </div>
  );
}

