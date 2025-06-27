# Super Simple MCP Deployment Guide

This guide explains how to get the Pierce County MCP Server running using Docker.
It uses very easy language so anyone can follow along.

## 1. Build the Container
1. Open a terminal where this code lives.
2. Type `docker build -t pierce-mcp .` and press enter.
3. Docker mixes all the files together and makes an image. That's our server.

## 2. Run It Locally
1. After it builds, start the server with
   ```bash
   docker run -p 3000:3000 pierce-mcp
   ```
2. The server runs in the background. Visit `http://localhost:3000/health` to see if it's happy.

## 3. Deploy to Production
1. Instead of a single container, use `docker-compose` to manage everything.
   ```bash
   docker compose up -d
   ```
2. This uses `docker-compose.yml` to launch the server with logs and data folders on your machine.

## 4. Monitor and Troubleshoot
- The container checks itself with a special script every 30 seconds.
- Look at the `logs/` folder to see what it's doing.
- If something breaks, run `docker compose logs` to read the messages.

## 5. Scale and Update
- To run more copies, change `replicas` in `k8s/deployment.yaml` and apply it with kubectl.
- To update, build a new image and run `docker compose up -d` again. The old one stops and the new one takes over.

That's it! Now the MCP Server is running and easy to manage.
