#!/bin/bash

# Clone the repository
git clone https://github.com/NapthaAI/naptha-node.git
cd naptha-node

# Copy the example environment file
if [ ! -f .env ]; then
  cp .env.example .env
  echo ".env file created. Please edit it with your settings."
else
  echo ".env file already exists. Proceeding with existing settings."
fi

# Prompt for necessary environment variables if they are not set
if [ -z "$(grep "^PRIVATE_KEY=" .env | cut -d'=' -f2)" ]; then
    read -p "Enter PRIVATE_KEY: " PRIVATE_KEY
    echo "PRIVATE_KEY=$PRIVATE_KEY" >> .env
fi

if [ -z "$(grep "^HUB_USERNAME=" .env | cut -d'=' -f2)" ]; then
    read -p "Enter HUB_USERNAME: " HUB_USERNAME
    echo "HUB_USERNAME=$HUB_USERNAME" >> .env
fi

if [ -z "$(grep "^HUB_PASSWORD=" .env | cut -d'=' -f2)" ]; then
    read -sp "Enter HUB_PASSWORD: " HUB_PASSWORD
    echo ""
    echo "HUB_PASSWORD=$HUB_PASSWORD" >> .env
fi

read -p "Do you want to set OPENAI_API_KEY? (y/n): " set_openai
if [[ "$set_openai" == "y" || "$set_openai" == "Y" ]]; then
    read -p "Enter OPENAI_API_KEY: " OPENAI_API_KEY
    echo "OPENAI_API_KEY=$OPENAI_API_KEY" >> .env
fi

read -p "Do you want to set STABILITY_API_KEY? (y/n): " set_stability
if [[ "$set_stability" == "y" || "$set_stability" == "Y" ]]; then
    read -p "Enter STABILITY_API_KEY: " STABILITY_API_KEY
    echo "STABILITY_API_KEY=$STABILITY_API_KEY" >> .env
fi

# Launch the node
bash launch.sh

echo "Node launched. You can access it according to your configuration."
echo "Remember to set NODE_URL in the Naptha SDK to http://localhost:7001 (or your custom URL)."
