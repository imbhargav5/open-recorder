import { useEffect, useState } from 'react'

export interface MicrophoneDevice {
  deviceId: string
  label: string
  groupId: string
}

export function useMicrophoneDevices(enabled: boolean = true) {
  const [devices, setDevices] = useState<MicrophoneDevice[]>([])
  const [selectedDeviceId, setSelectedDeviceId] = useState<string>('default')
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!enabled) {
      return
    }

    const mediaDevices = navigator.mediaDevices
    if (!mediaDevices?.enumerateDevices) {
      setDevices([])
      setError('Microphone device listing is unavailable in this window')
      setIsLoading(false)
      return
    }

    let mounted = true

    const loadDevices = async () => {
      try {
        setIsLoading(true)
        setError(null)

        const allDevices = await mediaDevices.enumerateDevices()
        const audioInputs = allDevices
          .filter((device) => device.kind === 'audioinput' && device.deviceId !== '')
          .map((device) => ({
            deviceId: device.deviceId,
            label: device.label || `Microphone ${device.deviceId.slice(0, 8)}`,
            groupId: device.groupId,
          }))

        if (mounted) {
          setDevices(audioInputs)
          setIsLoading(false)
        }
      } catch (error) {
        if (mounted) {
          const message = error instanceof Error ? error.message : 'Failed to enumerate audio devices'
          setError(message)
          setIsLoading(false)
          console.error('Error loading microphone devices:', error)
        }
      }
    }

    void loadDevices()

    const handleDeviceChange = () => {
      void loadDevices()
    }

    mediaDevices.addEventListener?.('devicechange', handleDeviceChange)

    return () => {
      mounted = false
      mediaDevices.removeEventListener?.('devicechange', handleDeviceChange)
    }
  }, [enabled])

  return {
    devices,
    selectedDeviceId,
    setSelectedDeviceId,
    isLoading,
    error,
  }
}
