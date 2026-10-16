# DevOps SLA Assignment — Task 4: Docker
## Practical Implementation: Containerizing MKES CARE+ Flutter Web with Nginx

---

| **Academic Information** | **Details** |
| :--- | :--- |
| **Course / Subject** | DevOps SLA (Software Lifecycle Automation) |
| **Assignment Task** | **Task 4: Docker** |
| **Aim** | Create a Docker image of MKES CARE+ web application, run it on port 8081, open it in browser, and verify Supabase database connectivity. |
| **Project Location** | `D:\mkes-lovable` (Flutter Web Platform) |
| **Docker Artifacts** | Image: `mkes-care-plus:latest` (153 MB)  |  Container: `mkes-care-web` |
| **Port Mapping** | `http://localhost:8081` (Host Port 8081 -> Container Port 80) |
| **Backend / Database** | Supabase PostgreSQL (External Cloud BaaS over client-side HTTPS/REST) |

---

## 1. Dockerfile Creation and Explanation

A `Dockerfile` was created in the root directory (`D:\mkes-lovable\Dockerfile`) to package the static web application with a lightweight Nginx web server:

```dockerfile
FROM nginx:alpine
COPY build/web /usr/share/nginx/html
EXPOSE 80
```

### Explanation:
- **`FROM nginx:alpine`**: Uses the official Nginx web server based on Alpine Linux (~5 MB base). The resulting image is lightweight (153 MB total), secure, and quick to build.
- **`COPY build/web /usr/share/nginx/html`**: Copies the compiled static Flutter web files into Nginx's public web root.
- **`EXPOSE 80`**: Documents that the Nginx web server inside the container listens on port 80.

---

## 2. Generating the Flutter Web Build

Before building the Docker image, the Flutter application was compiled into production web artifacts using PowerShell in `D:\mkes-lovable`:

```powershell
PS D:\mkes-lovable> flutter build web
```

This command compiles Dart code into JavaScript (`main.dart.js`), bundles CanvasKit WebAssembly modules, and generates the static files in `build/web`, which Nginx serves.

![Figure 1 — Flutter Web Build Process](assets/fig1_flutter_build_web.png)
*Figure 1 — Compiling MKES CARE+ to Web Assembly and Static JavaScript Assets using 'flutter build web'*

> **Verification:** Confirms `flutter devices` detecting web targets followed by successful execution of `flutter build web` in `D:\mkes-lovable`.

---

## 3. Building the Docker Image

The Docker image was built from the project root using the following command:

```powershell
PS D:\mkes-lovable> docker build -t mkes-care-plus .
```

- **`-t mkes-care-plus`**: Assigns the image name `mkes-care-plus` (tagged `:latest` by default).
- **`.` (dot)**: Specifies the build context as the current directory (`D:\mkes-lovable`).

![Figure 2a — Docker BuildKit Engine Exporting Layers](assets/fig2a_docker_build_progress.png)
*Figure 2a — Docker BuildKit Engine Exporting Layers and Committing Manifest*

---

## 4. Running the Docker Container

The container was launched in background detached mode mapped to host port **8081**:

```powershell
PS D:\mkes-lovable> docker run -d --name mkes-care-web -p 8081:80 mkes-care-plus
```

- **`-d`**: Detached mode (runs the container in the background).
- **`--name mkes-care-web`**: Assigns the custom container name `mkes-care-web`.
- **`-p 8081:80`**: Maps host port 8081 to container port 80 (`<HostPort>:<ContainerPort>`). Port 8081 was chosen to prevent conflicts with common development services running on port 8080.
- **Returned Container ID**: `d7342578d852d1ec1f84e83dd6522ac24bc4278ca21314a5bb529fcf9332cc9b`.

---

## 5. Verifying the Image and Running Container

The created image and running container status were verified using CLI commands:

```powershell
PS D:\mkes-lovable> docker images mkes-care-plus
IMAGE                   ID             DISK USAGE   CONTENT SIZE   EXTRA
mkes-care-plus:latest   bd5becd1da2b   153MB        41.2MB

PS D:\mkes-lovable> docker ps -a
CONTAINER ID   IMAGE            STATUS         PORTS                                            NAMES
d7342578d852   mkes-care-plus   Up About a min 0.0.0.0:8081->80/tcp, [::]:8081->80/tcp         mkes-care-web
```

![Figure 2 — Terminal Output: Docker Image Verification, Run, and Process Status](assets/fig2_docker_build_run_ps.png)
*Figure 2 — Terminal Output: Docker Image Verification, Detached Container Launch ('mkes-care-web'), and Process Status ('docker ps -a')*

> **Verification:** Proves: (1) Image verification (ID `bd5becd1da2b`, 153 MB), (2) Container execution with assigned ID `d7342578...`, and (3) `docker ps -a` verifying status `Up` on `0.0.0.0:8081->80/tcp`.

![Figure 3 — Docker Desktop Dashboard Inspection](assets/fig3_docker_desktop_details.png)
*Figure 3 — Docker Desktop Dashboard: GUI Verification of 'mkes-care-web' Container, Port Mapping 8081:80, and Nginx Server Logs*

> **Verification:** GUI verification in Docker Desktop confirming container `mkes-care-web`, port mapping `8081:80`, and Nginx server process management logs.

---

## 6. Accessing the Application in the Browser

Open any browser and navigate to:

```
http://localhost:8081
```

- **Flow:** Nginx serves the compiled Flutter web files. The Flutter engine boots and initializes Supabase from `api.env`.
- **Authentication Portal:** Since no session is stored, `AuthWrapper` automatically displays the Role Selection / Login screen, offering **Admin Portal** (admin & doctors) and **Staff Portal** (receptionists & assistants).

---

## 7. Supabase Database Connectivity & Security

- **External Backend Architecture:** The Docker container hosts **ONLY** the Nginx static web server. It does **NOT** contain PostgreSQL. The database is hosted externally on Supabase (`*.supabase.co`). The Flutter client in the browser makes direct outbound HTTPS/REST and WebSocket requests to Supabase.
- **Live Demonstration Evidence:** When navigating to staff management, the application queries the PostgreSQL `profiles` table, retrieving active staff accounts and real-time shift records.

![Figure 4 — MKES CARE+ Application Interface: Real-time Supabase Database Operations](assets/fig4_mkes_care_staff_management.png)
*Figure 4 — MKES CARE+ Application Interface: Real-time Supabase Database Operations and Clinical Records Display*

> **Verification:** Validates live database queries retrieving staff profiles (`Tirtha`, `Riya`) and mutation toast: *"Shift saved for Tirtha, but notification delivery failed. Please use Retry."*, proving end-to-end database connectivity.

> [!CAUTION]
> **CRITICAL SECURITY NOTE:**  
> **Public Inspectability of Web Assets:** In Flutter Web, `api.env` is bundled under `assets/` and can be viewed by anyone at `http://localhost:8081/assets/api.env`. Therefore, `api.env` must **ONLY** contain public client keys (`SUPABASE_URL` and `SUPABASE_ANON_KEY`). Never include `service_role` keys, database passwords, or secret tokens. Database security relies strictly on PostgreSQL **Row Level Security (RLS)** policies.

---

## 8. Essential Docker Commands Reference

| Purpose | Command |
| :--- | :--- |
| **Build image** | `docker build -t mkes-care-plus .` |
| **Run container** | `docker run -d --name mkes-care-web -p 8081:80 mkes-care-plus` |
| **List running containers** | `docker ps` |
| **List all containers** | `docker ps -a` |
| **View container logs** | `docker logs mkes-care-web` |
| **Stop container** | `docker stop mkes-care-web` |

---

## 9. Result and Conclusion

**Result:**  
A compact Docker image `mkes-care-plus:latest` (153 MB) was built using `nginx:alpine`. The container `mkes-care-web` was deployed in detached mode with host port 8081 mapped to container port 80. The application was successfully verified via CLI (`docker ps -a`) and Docker Desktop GUI, and accessed in the browser at `http://localhost:8081`.

**Conclusion:**  
1. **Lightweight Deployment:** Nginx Alpine provides an ultra-compact, high-performance static host for Flutter web apps.
2. **Clean Architectural Separation:** The Docker container isolates the frontend web server, while data persistence remains securely managed in the cloud by Supabase PostgreSQL.
3. **Security Awareness:** Public web distributions must never bundle privileged backend secrets; authorization is enforced via database Row Level Security (RLS).

---

## 10. Practical Viva Questions & Answers

**Q1: Why did we choose `nginx:alpine` as the base image?**  
*Answer:* Alpine Linux is an ultra-minimal distribution (~5 MB base). Nginx is ideal for serving Flutter's static HTML/JS assets. The final image is only 153 MB, compared to 500+ MB for Ubuntu-based images.

**Q2: What does `-p 8081:80` mean in the `docker run` command?**  
*Answer:* It forwards host port 8081 to container internal port 80 (`<HostPort>:<ContainerPort>`). Port 8081 was chosen to prevent conflicts with common development tools running on port 8080.

**Q3: Does this Docker container run PostgreSQL or the Supabase database?**  
*Answer:* No. The container contains only Nginx and static frontend files. Supabase PostgreSQL is an external cloud BaaS; the browser communicates directly with it over HTTPS/REST.

**Q4: What is the security risk of including a `service_role` key in `api.env` for Flutter Web?**  
*Answer:* In Flutter Web, `api.env` is compiled into public assets reachable via HTTP. A `service_role` key would grant anyone full admin access to PostgreSQL. Only public `anon` keys should be in `api.env`, backed by Row Level Security (RLS).
