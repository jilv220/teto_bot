# Use the official Elixir image for a Linux environment
FROM elixir:1.18

# Install build dependencies for Bakeware
# RUN apt-get update && apt-get install -y \
#     build-essential \
#     git

# Set the working directory
WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy the mix.exs and mix.lock files to set up the app
COPY mix.exs mix.lock ./

# Install dependencies
RUN mix deps.get

# Copy the rest of your application code to the container
COPY . .

# Set the environment to production for cross-compilation
ENV MIX_ENV=prod

# Compile the application and build the release using Bakeware
RUN  mix release 

# Set up an entrypoint so we can manually extract the binary
ENTRYPOINT ["_build/prod/rel/teto_bot/bin/teto_bot", "start"]