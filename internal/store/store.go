package store

import (
	"sync"
	"time"

	"github.com/google/uuid"
)

type Item struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
}

type Store struct {
	mu    sync.RWMutex
	items map[string]Item
}

func New() *Store {
	return &Store{items: make(map[string]Item)}
}

func (s *Store) List() []Item {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]Item, 0, len(s.items))
	for _, item := range s.items {
		result = append(result, item)
	}
	return result
}

func (s *Store) Get(id string) (Item, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	item, ok := s.items[id]
	return item, ok
}

func (s *Store) Create(name, description string) Item {
	item := Item{
		ID:          uuid.NewString(),
		Name:        name,
		Description: description,
		CreatedAt:   time.Now().UTC(),
	}
	s.mu.Lock()
	s.items[item.ID] = item
	s.mu.Unlock()
	return item
}

func (s *Store) Update(id, name, description string) (Item, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	item, ok := s.items[id]
	if !ok {
		return Item{}, false
	}
	item.Name = name
	item.Description = description
	s.items[id] = item
	return item, true
}

func (s *Store) Delete(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.items[id]
	if ok {
		delete(s.items, id)
	}
	return ok
}
