"""
face_cache.py — In-memory cache for face vectors.
Loads all employee face vectors from DB into RAM at startup.
Scan comparisons run in pure Python/numpy — zero DB calls.
"""
import logging
import threading
from typing import Dict, Optional
import numpy as np

logger = logging.getLogger(__name__)

# Structure: { company_id: { employee_id: { "name": str, "vectors": [np.ndarray] } } }
_cache: Dict[int, Dict[int, dict]] = {}
_lock = threading.Lock()


def load_all(db_rows: list) -> None:
    """
    Load face vectors from DB rows into memory.
    Each row: (employee_id, company_id, name, face_vector_list)
    """
    new_cache: Dict[int, Dict[int, dict]] = {}
    for emp_id, company_id, name, vector in db_rows:
        if company_id not in new_cache:
            new_cache[company_id] = {}
        if emp_id not in new_cache[company_id]:
            new_cache[company_id][emp_id] = {"name": name, "vectors": []}
        arr = np.asarray(vector, dtype=np.float32)
        norm = np.linalg.norm(arr)
        if norm > 0:
            arr = arr / norm
        new_cache[company_id][emp_id]["vectors"].append(arr)

    with _lock:
        _cache.clear()
        _cache.update(new_cache)

    total_emps = sum(len(v) for v in new_cache.values())
    logger.info(f"✅ Face cache loaded: {total_emps} employees across {len(new_cache)} companies")


def add_employee(company_id: int, emp_id: int, name: str, vectors: list) -> None:
    """Add or update a single employee's vectors after registration."""
    with _lock:
        if company_id not in _cache:
            _cache[company_id] = {}
        _cache[company_id][emp_id] = {
            "name": name,
            "vectors": [np.asarray(v, dtype=np.float32) for v in vectors],
        }


def remove_employee(company_id: int, emp_id: int) -> None:
    """Remove employee from cache after deletion."""
    with _lock:
        if company_id in _cache:
            _cache[company_id].pop(emp_id, None)


def find_best_match(company_id: int, query_embedding: list, threshold: float = 0.45):
    """
    Compare query embedding against all cached vectors for a company.
    Returns (employee_id, name, similarity) or None if no match.
    Pure numpy — no DB call.
    """
    query = np.asarray(query_embedding, dtype=np.float32)
    norm = np.linalg.norm(query)
    if norm > 0:
        query = query / norm

    best_sim = -1.0
    best_id = None
    best_name = None

    with _lock:
        company_emps = _cache.get(company_id, {})

    for emp_id, data in company_emps.items():
        for vec in data["vectors"]:
            sim = float(np.dot(query, vec))
            if sim > best_sim:
                best_sim = sim
                best_id = emp_id
                best_name = data["name"]

    if best_id is not None and best_sim >= threshold:
        return best_id, best_name, best_sim
    return None
