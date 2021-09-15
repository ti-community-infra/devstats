package lib

type StringSet map[string]struct{}

func (s *StringSet) ToArray() []string {
	arr := make([]string, 0)
	if s == nil {
		return arr
	}
	for key := range *s {
		arr = append(arr, key)
	}
	return arr
}
