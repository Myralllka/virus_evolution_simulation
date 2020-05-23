//
// Created by fenix on 5/23/20.
//
#include "../../includes/objects/field.h"
#include <iostream>
#include "../../includes/objects/state_obj.h"


State NoneState = State{};

std::vector<Field::point> Field::infect_range(size_t x, size_t y) const {
    const std::vector<point> check_range = {{x + 1, y},
                                            {x,     y + 1},
                                            {x - 1, y},
                                            {x,     y - 1}};
    std::vector<point> res_range{};
    for (auto &check_p : check_range)
        // TODO: check order of boolean operations below
        if (((x == 0 && 1 >= check_p.x) || (x != 0 && check_p.x < matrix.size()))
            && ((y == 0 && 1 >= check_p.y) || (y != 0 && check_p.y < matrix[check_p.x].size())))
            res_range.emplace_back(check_p);
    return res_range;
}

Person &Field::get_person(const Field::point &p) {
    return matrix[p.x][p.y];
}

void Field::execute_interactions() {
    for (size_t x = 0; x < matrix.size(); ++x)
        for (size_t y = 0; y < matrix[x].size(); ++y) {
            auto temp_person = matrix[x][y];
            if (temp_person.is_alive() && (temp_person.is_infected() || temp_person.is_patient()))
                for (const auto &pos : infect_range(x, y))
                    get_person(pos).try_infect();
        }
}

Field::Field(size_t f_size) {
    for (size_t i = 0; i < f_size; ++i) {
        std::vector<Person> new_vector(f_size);
        for (size_t j = 0; j < f_size; ++j) {
            new_vector[j] = Person(States::normal, States::normal);
        }
        matrix.emplace_back(new_vector);
    }
}

void Field::show() const {
    for (const auto &row : matrix) {
        std::cout << "|";
        for (const Person &p : row) {
            std::cout << " " << p.get_repr() << " |";
        }
        std::cout << "\n";
    }
    std::cout << "\n========================================" << std::endl;
}

void Field::infect(size_t x, size_t y) {
    get_person(point{x, y}).set_timer(incubation_time);
    get_person(point{x, y}).become_infected();
}

void Field::change_the_era() {
    execute_interactions();
    for (auto &row : matrix)
        for (auto &person : row)
            person.evolute();
}
