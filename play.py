#!/usr/bin/env python3
import argparse
import os
import sys
import shutil
import subprocess
import platform
from pathlib import Path


def play_audio_file(file_path, silent=False, verbose=False):
    """Plays an audio file using the system's default audio player."""
    if not os.path.exists(file_path):
        if not silent:
            print(f"❌ Error: File '{file_path}' not found.")
        return False
    
    try:
        system = platform.system().lower()
        
        if verbose and not silent:
            print(f"🖥️  Detected system: {system}")
            print(f"🎵 Playing: {file_path}")
        
        if system == 'darwin':  # macOS
            if verbose and not silent:
                print("🍎 Using afplay (macOS built-in player)")
            subprocess.run(['afplay', file_path], check=True)
            
        elif system == 'linux':
            # Try common Linux audio players
            players = ['paplay', 'aplay', 'play', 'mpv', 'vlc']
            player_found = False
            
            for player in players:
                if shutil.which(player):
                    if verbose and not silent:
                        print(f"🎧 Using {player}")
                    
                    if player == 'vlc':
                        subprocess.run([player, '--intf', 'dummy', '--play-and-exit', file_path], 
                                     check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        subprocess.run([player, file_path], check=True)
                    player_found = True
                    break
            
            if not player_found:
                if not silent:
                    print("❌ Error: No suitable audio player found.")
                    print("💡 Please install one of: paplay, aplay, play, mpv, or vlc")
                return False
                
        elif system == 'windows':
            # Windows - use start command
            if verbose and not silent:
                print("🪟 Using Windows start command")
            subprocess.run(['start', '', file_path], shell=True, check=True)
            
        else:
            if not silent:
                print(f"❌ Error: Audio playback not supported on {system}")
            return False
            
        if not verbose and not silent:
            print(f"🎵 Playing: {os.path.basename(file_path)}")
        return True
        
    except subprocess.CalledProcessError as e:
        if not silent:
            print(f"❌ Error playing audio file: {e}")
        return False
    except FileNotFoundError as e:
        if not silent:
            print(f"❌ Error: Audio player not found - {e}")
        return False


def list_audio_files(directory):
    """List all audio files in a directory."""
    audio_extensions = {'.mp3', '.wav', '.flac', '.m4a', '.ogg', '.aac'}
    audio_files = []
    
    try:
        path = Path(directory)
        if not path.exists():
            print(f"Error: Directory '{directory}' not found.")
            return []
        
        for file_path in path.iterdir():
            if file_path.is_file() and file_path.suffix.lower() in audio_extensions:
                audio_files.append(file_path)
        
        return sorted(audio_files)
    except Exception as e:
        print(f"Error listing files: {e}")
        return []


def main():
    parser = argparse.ArgumentParser(description="Atten audio file player")
    
    parser.add_argument('file', nargs='?', help="Path to audio file to play")
    parser.add_argument('-d', '--directory', help="Play all audio files in a directory")
    parser.add_argument('-l', '--list', action='store_true', help="List audio files in current or specified directory")
    parser.add_argument('-v', '--verbose', action='store_true', help="Verbose output")
    parser.add_argument('--latest', action='store_true', help="Play the most recently created audio file in outputs directory")
    
    args = parser.parse_args()
    
    # Handle --latest option
    if args.latest:
        outputs_dir = 'outputs'
        if not os.path.exists(outputs_dir):
            print(f"Error: '{outputs_dir}' directory not found.")
            sys.exit(1)
        
        audio_files = list_audio_files(outputs_dir)
        if not audio_files:
            print(f"No audio files found in '{outputs_dir}' directory.")
            sys.exit(1)
        
        # Get the most recently modified file
        latest_file = max(audio_files, key=lambda f: f.stat().st_mtime)
        if args.verbose:
            print(f"Latest file: {latest_file}")
        play_audio_file(str(latest_file), args.verbose)
        return
    
    # Handle --list option
    if args.list:
        directory = args.directory or '.'
        audio_files = list_audio_files(directory)
        
        if not audio_files:
            print(f"No audio files found in '{directory}'")
        else:
            print(f"Audio files in '{directory}':")
            for audio_file in audio_files:
                print(f"  {audio_file.name}")
        return
    
    # Handle --directory option
    if args.directory:
        audio_files = list_audio_files(args.directory)
        
        if not audio_files:
            print(f"No audio files found in '{args.directory}'")
            sys.exit(1)
        
        print(f"Playing {len(audio_files)} audio file(s) from '{args.directory}':")
        for audio_file in audio_files:
            print(f"\nPlaying: {audio_file.name}")
            if not play_audio_file(str(audio_file), args.verbose):
                print(f"Failed to play: {audio_file.name}")
        return
    
    # Handle single file
    if args.file:
        if not play_audio_file(args.file, args.verbose):
            sys.exit(1)
    else:
        print("Error: Please specify a file to play or use --directory, --list, or --latest")
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
