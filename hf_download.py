import os
import re
import sys
import subprocess
import requests

HF_API = {
    "model": "https://huggingface.co/api/models",
    "dataset": "https://huggingface.co/api/datasets",
}


def parse_repo(repo):
    if repo.startswith("https://huggingface.co/"):
        repo = repo.replace("https://huggingface.co/", "")
        repo = repo.split("/tree")[0]
        repo = repo.split("/resolve")[0]
    return repo.strip("/")


def get_all_files(repo, repo_type="model"):
    url = f"{HF_API[repo_type]}/{repo}/tree/main"

    files = []
    cursor = None

    while True:
        params = {"recursive": "1"}

        if cursor:
            params["cursor"] = cursor

        r = requests.get(url, params=params)
        r.raise_for_status()

        data = r.json()

        for item in data:
            if item["type"] == "file":
                files.append({
                    "path": item["path"],
                    "size": item.get("size", -1)
                })

        link = r.links.get("next")
        if link is None:
            break

        m = re.search(r'cursor=([^&]+)', link["url"])
        if not m:
            break

        cursor = m.group(1)

    return files


def download(repo, file_info, save_dir, repo_type="model"):

    filename = file_info["path"]
    remote_size = file_info["size"]

    if repo_type == "model":
        url = f"https://huggingface.co/{repo}/resolve/main/{filename}"
    else:
        url = f"https://huggingface.co/datasets/{repo}/resolve/main/{filename}"

    repo_name = repo.split("/")[-1]
    local = os.path.join(save_dir, repo_name, filename)

    os.makedirs(os.path.dirname(local), exist_ok=True)

    # ===== 文件完整性检查 =====
    if os.path.exists(local):

        local_size = os.path.getsize(local)

        if remote_size > 0 and local_size == remote_size:
            print(f"[Skip] {filename}")
            return

        print(f"[Resume] {filename}")
        print(f"    Local : {local_size}")
        print(f"    Remote: {remote_size}")

    token = os.environ.get("HF_TOKEN")

    cmd = [
        "wget",
        "--header",
        f"Authorization: Bearer {token}",
        "-c",
        "-O",
        local,
        url,
    ]

    subprocess.run(cmd)

def main():

    if len(sys.argv) not in (3,4):
        print("Usage:")
        print("python hf_download.py model openai/clip-vit-large-patch14 local_save_dir")
        print("python hf_download.py dataset ILSVRC/imagenet-1k local_save_dir")
        return

    repo_type = sys.argv[1]
    repo = parse_repo(sys.argv[2])

    save_dir = sys.argv[3] if len(sys.argv)==4 else "."

    files = get_all_files(repo, repo_type)

    print("Found", len(files), "files")

    for f in files:
        download(repo, f, save_dir, repo_type)

if __name__ == "__main__":
    main()