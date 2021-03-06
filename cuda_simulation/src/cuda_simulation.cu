//
// Created by fenix on 6/13/20.
//
#include <cuda_simulation.cuh>
#include <cuda_assert.cuh>

#define NAMED_OUTPUT
#define DEBUG
#define THREADS 1024u

#ifdef DEBUG

#include <bitset>
#include <vector>

#endif // DEBUG


__global__ void
init_working_set(uint8_t *d_field, uint8_t *d_next_field, size_t field_side_len, curandState_t *d_rand_gen_arr,
                 size_t *d_isolation_places_arr, size_t isol_place, Statistics *d_res_stats) {
    curandState_t state;
    curand_init(clock64() - 1u, /* the seed controls the sequence of random values that are produced */
                0,        /* the sequence number is only important with multiple cores */
                0,             /* the offset is how much extra we advance in the sequence for each call, can be 0 */
                &state);

//     fills with IMMUNITY_ID by default
    fill_array_border(d_field, field_side_len);
    fill_array_border(d_next_field, field_side_len);
//     infect first cell
    size_t first_infected_coord = coord((curand(&state) % (field_side_len - 2u)) + 1u,
                                        (curand(&state) % (field_side_len - 2u)) + 1u,
                                        field_side_len);
    d_field[first_infected_coord] = INFECTED_ID;
    d_next_field[first_infected_coord] = INFECTED_ID;

    // init random generator for each thread
    for (size_t offset = 0; offset <= THREADS; ++offset)
        curand_init(clock64(),
                    offset,
                    0u,
                    &d_rand_gen_arr[offset]);

    // distribute isol places for each thread
    // TODO: check if isol_place is decidable by THREADS
    const size_t isol_place_per_thread = isol_place / THREADS;
    for (size_t i = 0; i < THREADS; ++i)
        d_isolation_places_arr[i] = isol_place_per_thread;

    *d_res_stats = Statistics{};
}

void cuda_simulation(const ConfigFileOpt &config) {
    const size_t field_side_len = config.field_size + 2u;

//  probabilities from one state to next state
//  healthy -> infected -> patient -> patient_critical(only one era) -> dead
//                                                                   -> immunity
    // TODO: load into CUDA_CONST_MEMORY
    const float probab_arr[NUMBER_OF_STATES] = {config.healthy_to_infected,         // healthy
                                                config.infected_to_patient,         // infected
                                                config.patient_coefficient,         // patient
                                                config.patient_to_dead,             // patient_crit
                                                FINAL_NEXT_STATE_PROBAB,            // dead
                                                FINAL_NEXT_STATE_PROBAB,            //
                                                FINAL_NEXT_STATE_PROBAB,            //
                                                FINAL_NEXT_STATE_PROBAB,            //
                                                FINAL_NEXT_STATE_PROBAB};           // immunity

    ///////////////////////// INIT WORKING FIELDS //////////////////////////

    uint8_t *d_field, *d_next_field;
    // TODO: move probab_arr to const memory
    float *d_probab_arr;
    curandState_t *d_rand_gen_arr;
    size_t *d_isolation_places_arr;
    Statistics *d_res_stats, res_stats{};

    gpuErrorCheck(cudaMalloc((void **) &d_field, field_side_len * field_side_len * sizeof(uint8_t)))//
    gpuErrorCheck(cudaMalloc((void **) &d_next_field, field_side_len * field_side_len * sizeof(uint8_t)))//
    gpuErrorCheck(cudaMalloc((void **) &d_probab_arr, NUMBER_OF_STATES * sizeof(float)))//
    gpuErrorCheck(cudaMalloc((void **) &d_rand_gen_arr, THREADS * sizeof(curandState_t)))//
    gpuErrorCheck(cudaMalloc((void **) &d_isolation_places_arr, THREADS * sizeof(size_t)))//
    gpuErrorCheck(cudaMalloc((void **) &d_res_stats, sizeof(Statistics)))//

    gpuErrorCheck(cudaMemcpy(d_probab_arr, probab_arr, NUMBER_OF_STATES * sizeof(float), cudaMemcpyHostToDevice))//
    gpuErrorCheck(cudaMemset(static_cast<void *>(d_field), 0, field_side_len * field_side_len * sizeof(uint8_t)))//
    gpuErrorCheck(cudaMemset(static_cast<void *>(d_next_field), 0, field_side_len * field_side_len * sizeof(uint8_t)))//

    init_working_set<<<1, 1>>>(d_field, d_next_field, field_side_len, d_rand_gen_arr, d_isolation_places_arr,
                               config.isol_place, d_res_stats);
    ///////////////////////// END INIT WORKING FIELDS //////////////////////

    std::cout << "1\n" << config.field_size * config.field_size << std::endl;
    // indicate witch d_field is current and witch next
    bool next = true;

    for (size_t i = 0u; i < config.num_of_eras; ++i) {
        // TODO: assert thread is a square root of integer
        dim3 worker_space(std::sqrt(THREADS), std::sqrt(THREADS));
        if (next)
            sim_block_worker<<<1, worker_space>>>(d_field, d_next_field, field_side_len, d_probab_arr,
                                                  d_isolation_places_arr, d_rand_gen_arr, d_res_stats);
        else
            sim_block_worker<<<1, worker_space>>>(d_next_field, d_field, field_side_len, d_probab_arr,
                                                  d_isolation_places_arr, d_rand_gen_arr, d_res_stats);

        gpuErrorCheck(cudaMemcpy(&res_stats, d_res_stats, sizeof(Statistics), cudaMemcpyDeviceToHost))//

        ///////////////////// OUTPUT OUTLAY ////////////////////
        // normal, immunity, infected, patient, isolated, dead;
#ifdef NAMED_OUTPUT
        std::cout << "immunity " << res_stats.immunity << " "
                  << "infected " << res_stats.infected << " "
                  << "patient " << res_stats.patient << " "
                  << "isolated " << res_stats.isolated << " "
                  << "dead " << res_stats.dead << std::endl;
#else
        std::cout << res_stats.immunity << " "
                  << res_stats.infected << " "
                  << res_stats.patient << " "
                  << res_stats.isolated << " "
                  << res_stats.dead << std::endl;
#endif // NAMED_OUTPUT
        if (res_stats.infected + res_stats.patient + res_stats.isolated == 0) {
            // finish simulation after system stabilization
            return;
        }
        ///////////////////// OUTPUT OUTLAY END ////////////////

        //////////////////////////////////// PRINT FIELD //////////////////////////////////////////
//        std::vector<uint8_t> v(field_side_len * field_side_len);
//        uint8_t *h_field = v.data();
//        if (!next) { gpuErrorCheck(cudaMemcpy(h_field, d_field, field_side_len * field_side_len * sizeof(uint8_t),
//                                              cudaMemcpyDeviceToHost))
//        } else { gpuErrorCheck(cudaMemcpy(h_field, d_next_field,
//                                          field_side_len * field_side_len * sizeof(uint8_t),
//                                          cudaMemcpyDeviceToHost));
//        }gpuErrorCheck(cudaMemcpy(&res_stats, d_res_stats, sizeof(Statistics), cudaMemcpyDeviceToHost))//
//
//        for (size_t row = 0; row < field_side_len; ++row) {
//            for (size_t col = 0; col < field_side_len; ++col)
//                switch (h_field[row * field_side_len + col]) {
//                    case HEALTHY_ID:
//                        std::cout << "." << " ";
//                        continue;
//                    case INFECTED_ID:
//                        std::cout << "*" << " ";
//                        continue;
//                    case PATIENT_ID:
//                        std::cout << "p" << " ";
//                        continue;
//                    case PATIENT_CRIT_ID:
//                        std::cout << "c" << " ";
//                        continue;
//                    case DEAD_ID:
//                        std::cout << "d" << " ";
//                        continue;
//                    case IMMUNITY_ID:
//                        std::cout << "i" << " ";
//                        continue;
//                    default:
//                        if (ISOLATE_MASK & h_field[row * field_side_len + col])
//                            std::cout << "_" << " ";
//                        else
//                            std::cout << "?" << " ";
//                        continue;
//                }
//
//
////                std::cout << std::bitset<8>(h_field[row * field_side_len + col]) << " ";
//            std::cout << std::endl;
//        }
        //////////////////////////////////// PRINT FIELD  END /////////////////////////////////////

        next = !next;
    }

    gpuErrorCheck(cudaFree(d_rand_gen_arr))//
    gpuErrorCheck(cudaFree(d_isolation_places_arr))//
    gpuErrorCheck(cudaFree(d_res_stats))//
    gpuErrorCheck(cudaFree(d_probab_arr))//
    gpuErrorCheck(cudaFree(d_next_field))//
    gpuErrorCheck(cudaFree(d_field))//
}

__global__ void sim_block_worker(const uint8_t *d_field, uint8_t *d_next_field, size_t field_side_len,
                                 const float *probab_arr, size_t *d_isolation_places_arr, curandState_t *d_rand_gen_arr,
                                 Statistics *d_res_stats) {
    // TODO: assert that field_side_len / blockDim.x is fully dividable
    const size_t working_set_side = (field_side_len - 2u) / blockDim.x;
    const uint thread_id = threadIdx.x + blockDim.x * threadIdx.y;

    __shared__ uint stats_arr[THREADS * NUMBER_OF_STATES];
    for (size_t i = thread_id * NUMBER_OF_STATES; i < (thread_id + 1) * NUMBER_OF_STATES; ++i)
        stats_arr[i] = 0;

    uint8_t cell_st_id;
    size_t cell_coord;
    for (size_t row = 1u + working_set_side * threadIdx.y; row < 1u + working_set_side * (threadIdx.y + 1); ++row)
        for (size_t col = 1u + working_set_side * threadIdx.x; col < 1u + working_set_side * (threadIdx.x + 1); ++col) {
            cell_coord = coord(row, col, field_side_len);
            cell_st_id = d_field[cell_coord];

            if (cell_st_id & FINAL_STATE_CHECK_MASK) {}
            else if (cell_st_id == HEALTHY_ID) {
                infect_cell(d_field[coord(row - 1u, col, field_side_len)], cell_st_id, probab_arr,
                            &(d_rand_gen_arr[thread_id]));
                infect_cell(d_field[coord(row, col - 1u, field_side_len)], cell_st_id, probab_arr,
                            &(d_rand_gen_arr[thread_id]));
                infect_cell(d_field[coord(row, col + 1u, field_side_len)], cell_st_id, probab_arr,
                            &(d_rand_gen_arr[thread_id]));
                infect_cell(d_field[coord(row + 1u, col, field_side_len)], cell_st_id, probab_arr,
                            &(d_rand_gen_arr[thread_id]));
            } else {
                ///////////////////////////  ISOLATE IF POSSIBLE  /////////////////////////
                if (!(cell_st_id & ISOLATE_MASK))
                    if (cell_st_id == PATIENT_ID)
                        if (d_isolation_places_arr[thread_id]) {
                            --d_isolation_places_arr[thread_id];
                            cell_st_id = ISOLATE_MASK | PATIENT_ID;
                        }
                ///////////////////////////  ISOLATE IF POSSIBLE END  ///////////////////////

                ///////////////////////////  NEXT STATE  ///////////////////////
                if (random_bool(probab_arr[cell_st_id & REMOVE_ISOL_MASK], &(d_rand_gen_arr[thread_id]))) {
                    ++cell_st_id;
                    if ((cell_st_id & FINAL_STATE_CHECK_MASK) && (cell_st_id & ISOLATE_MASK)) {
                        ++d_isolation_places_arr[thread_id];
                        cell_st_id &= REMOVE_ISOL_MASK;
                    }
                } else if ((cell_st_id & REMOVE_ISOL_MASK) == PATIENT_CRIT_ID) {
                    if (cell_st_id & ISOLATE_MASK)
                        ++d_isolation_places_arr[thread_id];
                    cell_st_id = IMMUNITY_ID;
                }
                ///////////////////////////  NEXT STATE END  ///////////////////
            }


            /////////////////////////// STATISTICS GATHERING ///////////////////////
            if (cell_st_id & ISOLATE_MASK)
                // UNUSED_ID index is used for isolated count
                ++stats_arr[UNUSED_ID + thread_id * NUMBER_OF_STATES];
            else
                ++stats_arr[cell_st_id + thread_id * NUMBER_OF_STATES];
            /////////////////////////// STATISTICS GATHERING END ///////////////////
            d_next_field[cell_coord] = cell_st_id;
        }

//    for (size_t row = 1u + working_set_side * threadIdx.y; row < 1u + working_set_side * (threadIdx.y + 1); ++row)
//        for (size_t col = 1u + working_set_side * threadIdx.x; col < 1u + working_set_side * (threadIdx.x + 1); ++col) {
//            cell_coord = coord(row, col, field_side_len);
//            cell_st_id = d_field[cell_coord];
//            /////////////////////////// STATISTICS GATHERING ///////////////////////
//            if (cell_st_id & ISOLATE_MASK)
//                // UNUSED_ID index is used for isolated count
//                ++stats_arr[UNUSED_ID + thread_id * NUMBER_OF_STATES];
//            else
//                ++stats_arr[cell_st_id + thread_id * NUMBER_OF_STATES];
//        }
//            /////////////////////////// STATISTICS GATHERING END ///////////////////

    __syncthreads();
    if (thread_id == 0) {
        for (uint thread_offset = 0; thread_offset < THREADS; ++thread_offset) {
            stats_arr[HEALTHY_ID] += stats_arr[HEALTHY_ID + thread_offset * NUMBER_OF_STATES];
            stats_arr[IMMUNITY_ID] += stats_arr[IMMUNITY_ID + thread_offset * NUMBER_OF_STATES];
            stats_arr[INFECTED_ID] += stats_arr[INFECTED_ID + thread_offset * NUMBER_OF_STATES];
            stats_arr[PATIENT_ID] += stats_arr[PATIENT_ID + thread_offset * NUMBER_OF_STATES];
            stats_arr[UNUSED_ID] += stats_arr[UNUSED_ID + thread_offset * NUMBER_OF_STATES];
            stats_arr[DEAD_ID] += stats_arr[DEAD_ID + thread_offset * NUMBER_OF_STATES];
        }
        *d_res_stats = Statistics{stats_arr[HEALTHY_ID],
                                  stats_arr[IMMUNITY_ID],
                                  stats_arr[INFECTED_ID],
                                  stats_arr[PATIENT_ID] + stats_arr[PATIENT_CRIT_ID],
                                  stats_arr[UNUSED_ID],
                                  stats_arr[DEAD_ID]
        };
    }
}

