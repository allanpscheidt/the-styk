#!/bin/bash

# Ensure we are in the script's directory
cd "$(dirname "$0")"

# Check Python 3
if ! command -v python3 &> /dev/null; then
    echo "Erro: Python 3 não está instalado. Por favor, instale o Python 3."
    exit 1
fi

# Check PyGObject (gi) dependency
python3 -c "import gi" &> /dev/null
if [ $? -ne 0 ]; then
    echo "Erro: A dependência 'PyGObject' (gi) não foi encontrada."
    echo "Por favor, instale as dependências do sistema. Exemplo (Ubuntu/Debian):"
    echo "  sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-appindicator3-0.1"
    exit 1
fi

# Run the app
python3 src/main.py
