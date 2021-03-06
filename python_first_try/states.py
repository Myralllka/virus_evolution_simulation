from collections import defaultdict


class State:
    def __init__(self, new_id: int, new_repr: str,
                 prob: defaultdict = None):
        #        prob: DefaultDict[State, float] = None):
        """
        :param new_id: unique id of the state
        :param new_repr: string representation for visualization
        :param prob: probability get other state
        """
        self.id: int = new_id
        self.repr: str = new_repr
        self.prob: defaultdict = prob

    def __hash__(self):
        return hash(id)

    def __getitem__(self, item):
        return self.prob[item]

    def __eq__(self, other):
        return self.id == other.id

    def __repr__(self):
        return self.repr


class States:
    NORMAL = State(0, '.')
    INFECTED = State(1, '*')
    PATIENT = State(2, '0')
    DEAD = State(3, ' ')


class Statistics:
    def __init__(self, ok=0, infected=0, ill=0, dead=0):
        self.normal: int = ok
        self.infected: int = infected
        self.patient: int = ill
        self.dead: int = dead

    def total(self) -> int:
        return self.dead + self.infected + self.patient + self.normal


def init_states(states_class):
    states_class.NORMAL.prob = defaultdict(float, {States.INFECTED: 1 / 3})
    # static number of epoch's
    states_class.INFECTED.prob = defaultdict(float, {States.PATIENT: 1})
    states_class.PATIENT.prob = defaultdict(float, {States.DEAD: 1 / 3,
                                                    States.NORMAL: 2 / 3})
    states_class.DEAD.prob = defaultdict(float, {})


init_states(States)
