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

func FromArray(arr []string) StringSet {
	stringSet := make(StringSet, 0)
	for _, item := range arr {
		stringSet[item] = struct{}{}
	}

	return stringSet
}
